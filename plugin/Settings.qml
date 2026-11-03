import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "openMouse"
    property var discovered: []
    property var saved: loadValue("devices", [])
    property string selected: loadValue("selectedDeviceId", "")
    property string scanMessage: ""

    function select(device) {
        selected = device.device_id;
        saveValue("selectedDeviceId", selected);
    }
    function add(device) {
        if (!saved.some(item => item.device_id === device.device_id)) {
            saved = saved.concat([device]);
            saveValue("devices", saved);
        }
        select(device);
    }

    StyledText { text: "已添加设备"; color: Theme.surfaceText }
    Repeater {
        model: root.saved
        delegate: Row {
            required property var modelData
            spacing: Theme.spacingS
            DButton {
                text: (root.selected === modelData.device_id ? "✓ " : "") + modelData.name
                onClicked: root.select(modelData)
            }
            DButton {
                text: "移除"
                onClicked: {
                    root.saved = root.saved.filter(item => item.device_id !== modelData.device_id);
                    root.saveValue("devices", root.saved);
                    if (root.selected === modelData.device_id) {
                        root.selected = root.saved.length ? root.saved[0].device_id : "";
                        root.saveValue("selectedDeviceId", root.selected);
                    }
                }
            }
        }
    }
    DButton {
        text: scan.running ? "扫描中…" : "扫描设备"
        iconName: "search"
        enabled: !scan.running && !!root.pluginService
        onClicked: { root.scanMessage = ""; scan.running = true; }
    }
    StyledText {
        width: parent.width
        visible: root.scanMessage.length > 0
        text: root.scanMessage
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
    }
    Repeater {
        model: root.discovered
        delegate: DButton {
            required property var modelData
            text: "添加 " + modelData.name + "（" + modelData.device_id + "）"
            enabled: !root.saved.some(item => item.device_id === modelData.device_id)
            onClicked: root.add(modelData)
        }
    }
    Process {
        id: scan
        command: [root.pluginService ? root.pluginService.getPluginPath("openMouse") + "/bin/dms-openmouse" : ""]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify({id: "scan", method: "list_devices"}) + "\n");
            stdinEnabled = false;
        }
        onRunningChanged: if (running) stdinEnabled = true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reply = JSON.parse(text);
                    if (reply.error) throw new Error(reply.error.message);
                    root.discovered = reply.result;
                    root.scanMessage = reply.result.length ? "点击添加设备，添加后将用于面板显示" : "未发现支持的设备，请检查连接";
                } catch (error) { root.scanMessage = "扫描失败：" + error.message; }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.scanMessage = "扫描进程失败：" + exitCode; }
    }
}
