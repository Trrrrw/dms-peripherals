import QtQuick
import Quickshell.Io

Item {
    id: root
    property string backendPath: Qt.resolvedUrl("../backend/target/debug/dms-openmouse").toString().replace(/^file:\/\//, "")
    property var status: null
    property string message: "正在连接"
    property bool busy: false

    function refresh() {
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
            fail(reply.error.message);
        } else if (reply.id === "devices") {
            if (!reply.result.length) {
                fail("未发现设备");
                return;
            }
            backend.write(JSON.stringify({id: "status", method: "get_status", device_id: reply.result[0].device_id}) + "\n");
        } else if (reply.id === "status") {
            status = reply.result;
            message = "";
            busy = false;
            watchdog.stop();
        }
    }

    function fail(text) {
        status = null;
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
