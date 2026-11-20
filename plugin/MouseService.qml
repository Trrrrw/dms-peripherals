import QtQuick
import Quickshell.Io

Item {
    id: root
    property string backendPath: Qt.resolvedUrl("../backend/target/debug/dms-peripherals").toString().replace(/^file:\/\//, "")
    property string selectedDeviceId: ""
    onSelectedDeviceIdChanged: {
        status = null;
        details = null;
        history = [];
        operationMessage = "";
        lastSuccess = "";
        acquiredAt = 0;
        lastAttemptAt = 0;
        pendingSetting = null;
        message = selectedDeviceId ? "正在连接" : "请在设置中添加设备";
        restore();
        refresh();
    }
    property var stateStore: null
    property string stateId: "peripherals"
    onStateStoreChanged: restore()

    function restore() {
        if (!stateStore || !selectedDeviceId) return;
        history = stateStore.loadPluginState(stateId, "history:" + selectedDeviceId, []);
        if (status) return;
        const cached = stateStore.loadPluginState(stateId, "reading:" + selectedDeviceId, stateStore.loadPluginState(stateId, "lastReading", null));
        if (!cached || !cached.status || (selectedDeviceId && cached.status.device_id !== selectedDeviceId) || typeof cached.status.battery_percent !== "number" || typeof cached.time !== "string")
            return;
        status = cached.status;
        details = cached.details || null;
        acquiredAt = cached.acquiredAt || 0;
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

    property double lastAttemptAt: 0
    property bool writing: false
    property var pendingSetting: null
    onBusyChanged: {
        if (!busy && pendingSetting) {
            const pending = pendingSetting;
            pendingSetting = null;
            Qt.callLater(() => setSetting(pending.key, pending.value));
        }
    }
    function ensureFresh(maxAgeMs) {
        const limit = maxAgeMs === undefined ? 30000 : maxAgeMs;
        if (busy || Date.now() - Math.max(acquiredAt, lastAttemptAt) < limit) return;
        refresh();
    }
    function readDetails() { operation("get_details", "", null); }
    function setSetting(key, value) {
        if (busy) {
            if (!writing) {
                pendingSetting = {key: key, value: value};
                writing = true;
            }
            return;
        }
        operation("set_setting", key, value);
    }
    function operation(method, key, value) {
        if (!selectedDeviceId || !backend.running || busy) return;
        busy = true;
        writing = method === "set_setting";
        lastAttemptAt = Date.now();
        operationMessage = method === "set_setting" ? "正在写入并回读…" : "正在读取设备设置…";
        watchdog.restart();
        backend.write(JSON.stringify({id: method, method: method, device_id: selectedDeviceId, key: key, value: value}) + "\n");
    }

    property var status: null
    property string message: "正在连接"
    property bool busy: false
    property string lastSuccess: ""
    property double acquiredAt: 0

    function refresh() {
        if (!selectedDeviceId) {
            status = null;
            message = "请在设置中添加设备";
            return;
        }
        if (!backend.running || busy)
            return;
        readDetails();
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
            acquiredAt = Date.now();
            lastSuccess = Qt.formatDateTime(new Date(acquiredAt), "yyyy-MM-dd hh:mm:ss");
            if (stateStore) stateStore.savePluginState(stateId, "reading:" + selectedDeviceId, {status: status, time: lastSuccess, acquiredAt: acquiredAt, details: details});
            recordHistory();
            message = "";
            operationMessage = reply.id === "set_setting" ? "设置已写入，回读一致" : "";
            busy = false;
            writing = false;
            watchdog.stop();
        } else if (reply.id === "status") {
            if (!selectedDeviceId || reply.result.device_id !== selectedDeviceId) {
                busy = false;
                watchdog.stop();
                Qt.callLater(refresh);
                return;
            }
            status = reply.result;
            acquiredAt = Date.now();
            lastSuccess = Qt.formatDateTime(new Date(acquiredAt), "yyyy-MM-dd hh:mm:ss");
            if (stateStore)
                stateStore.savePluginState(stateId, "reading:" + selectedDeviceId, {status: status, time: lastSuccess, acquiredAt: acquiredAt, details: details});
            recordHistory();
            message = "";
            busy = false;
            writing = false;
            watchdog.stop();
        }
    }

    function fail(text) {
        pendingSetting = null;
        message = text;
        busy = false;
        writing = false;
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
        stderr: SplitParser { onRead: line => console.warn("Peripherals:", line) }
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
        onTriggered: root.ensureFresh(29000)
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
