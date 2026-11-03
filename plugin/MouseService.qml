import QtQuick
import Quickshell.Io

Item {
    id: root
    property string backendPath: Qt.resolvedUrl("../backend/target/debug/dms-openmouse").toString().replace(/^file:\/\//, "")
    property string selectedDeviceId: ""
    onSelectedDeviceIdChanged: {
        status = null;
        details = null;
        history = [];
        operationMessage = "";
        lastSuccess = "";
        message = selectedDeviceId ? "正在连接" : "请在设置中添加设备";
        restore();
        refresh();
    }
    property var stateStore: null
    property string stateId: "openMouse"
    onStateStoreChanged: restore()

    function restore() {
        if (!stateStore || !selectedDeviceId) return;
        history = stateStore.loadPluginState(stateId, "history:" + selectedDeviceId, []);
        if (status) return;
        const cached = stateStore.loadPluginState(stateId, "reading:" + selectedDeviceId, stateStore.loadPluginState(stateId, "lastReading", null));
        if (!cached || !cached.status || (selectedDeviceId && cached.status.device_id !== selectedDeviceId) || typeof cached.status.battery_percent !== "number" || typeof cached.time !== "string")
            return;
        status = cached.status;
        lastSuccess = cached.time;
        message = "正在刷新，当前显示历史数据";
    }

    property var history: []
    function recordHistory() {
        if (!status || typeof status.battery_percent !== "number") return;
        const now = Date.now();
        const recent = history.filter(point => point.time >= now - 7 * 86400000);
        if (recent.length && now - recent[recent.length - 1].time < 300000) return;
        history = recent.concat([{time: now, percent: status.battery_percent}]).slice(-2016);
        if (stateStore) stateStore.savePluginState(stateId, "history:" + selectedDeviceId, history);
    }
    property var details: null
    property string operationMessage: ""

    function readDetails() { operation("get_details", "", null); }
    function setSetting(key, value) { operation("set_setting", key, value); }
    function operation(method, key, value) {
        if (!selectedDeviceId || !backend.running || busy) return;
        busy = true;
        operationMessage = method === "set_setting" ? "正在写入并回读…" : "正在读取设备设置…";
        watchdog.restart();
        backend.write(JSON.stringify({id: method, method: method, device_id: selectedDeviceId, key: key, value: value}) + "\n");
    }

    property var status: null
    property string message: "正在连接"
    property bool busy: false
    property string lastSuccess: ""

    function refresh() {
        if (!selectedDeviceId) {
            status = null;
            message = "请在设置中添加设备";
            return;
        }
        if (!backend.running || busy)
            return;
        busy = true;
        watchdog.restart();
        backend.write(JSON.stringify({id: "devices", method: "list_devices"}) + "\n");
    }

    function receive(line) {
        let reply;
        try { reply = JSON.parse(line); }
        catch (error) {
            fail("后端返回无效数据");
            return;
        }
        if (reply.error) {
            operationMessage = "";
            fail(reply.error.message);
        } else if (reply.id === "devices") {
            if (!reply.result.length) {
                fail("未发现设备");
                return;
            }
            const device = reply.result.find(item => item.device_id === selectedDeviceId);
            if (!device) { fail("所选设备未连接"); return; }
            backend.write(JSON.stringify({id: "status", method: "get_status", device_id: device.device_id}) + "\n");
        } else if (reply.id === "get_details" || reply.id === "set_setting") {
            details = reply.result;
            const value = details.status;
            status = {device_id: selectedDeviceId, reported_name: value.name, battery_percent: value.batteryPercent,
                charging: value.batteryState === "Charging", dpi: value.dpi, polling_rate_hz: value.pollingRateHz};
            lastSuccess = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
            if (stateStore) stateStore.savePluginState(stateId, "reading:" + selectedDeviceId, {status: status, time: lastSuccess});
            recordHistory();
            message = "";
            operationMessage = reply.id === "set_setting" ? "设置已写入，回读一致" : "";
            busy = false;
            watchdog.stop();
        } else if (reply.id === "status") {
            if (!selectedDeviceId || reply.result.device_id !== selectedDeviceId) {
                busy = false;
                watchdog.stop();
                Qt.callLater(refresh);
                return;
            }
            status = reply.result;
            lastSuccess = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
            if (stateStore)
                stateStore.savePluginState(stateId, "reading:" + selectedDeviceId, {status: status, time: lastSuccess});
            recordHistory();
            message = "";
            busy = false;
            watchdog.stop();
        }
    }

    function fail(text) {
        message = text;
        busy = false;
        watchdog.stop();
    }

    Process {
        id: backend
        command: [root.backendPath]
        stdinEnabled: true
        running: root.backendPath.length > 0
        onStarted: root.refresh()
        onExited: {
            root.fail("后端已退出，正在重试");
            retry.restart();
        }
        stdout: SplitParser { onRead: line => root.receive(line) }
        stderr: SplitParser { onRead: line => console.warn("OpenMouse:", line) }
    }
    Timer {
        id: retry
        interval: 5000
        onTriggered: backend.running = true
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            root.fail("读取超时");
            backend.running = false;
        }
    }
}
