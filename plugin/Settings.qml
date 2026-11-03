import QtQuick
import QtQuick.Layouts
import Quickshell
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

    readonly property var selectedDevice: discovered.find(item => item.device_id === selected) || saved.find(item => item.device_id === selected) || null
    readonly property string permissionCommands: {
        const device = selectedDevice;
        if (!device || !/^[0-9a-f]{4}$/.test(device.vendor_id || "") || !/^[0-9a-f]{4}$/.test(device.product_id || "")) return "";
        const rule = 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="' + device.vendor_id + '", ATTRS{idProduct}=="' + device.product_id + '", TAG+="uaccess"';
        return "echo '" + rule + "' | sudo tee /etc/udev/rules.d/70-openmouse-" + device.vendor_id + "-" + device.product_id + ".rules\nsudo udevadm control --reload-rules";
    }

    function select(device) {
        selected = device.device_id;
        saveValue("selectedDeviceId", selected);
    }
    function removeDevice(deviceId) {
        const remaining = saved.filter(item => item.device_id !== deviceId);
        if (selected === deviceId) {
            selected = remaining.length ? remaining[0].device_id : "";
            saveValue("selectedDeviceId", selected);
        }
        saveValue("devices", remaining);
        // Updating the repeater destroys the clicked delegate; keep mutations here.
        saved = remaining;
    }

    function add(device) {
        if (!saved.some(item => item.device_id === device.device_id)) {
            saved = saved.concat([device]);
            saveValue("devices", saved);
        }
        select(device);
    }

    StyledText {
        text: "已添加设备"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }
    StyledText {
        visible: root.saved.length === 0
        text: "尚未添加设备，扫描后选择要显示的鼠标"
        color: Theme.surfaceVariantText
    }
    Repeater {
        model: root.saved
        delegate: Rectangle {
            required property var modelData
            width: parent.width
            implicitHeight: savedRow.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: root.selected === modelData.device_id ? 1 : 0
            border.color: Theme.primary
            RowLayout {
                id: savedRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM
                DIcon { name: "mouse"; size: 24; color: Theme.primary }
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; color: Theme.surfaceText }
                    StyledText { text: root.selected === modelData.device_id ? "面板显示中" : "已添加"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
                DButton { text: "使用"; visible: root.selected !== modelData.device_id; onClicked: root.select(modelData) }
                DButton { iconName: "delete"; tooltipText: "移除设备"; minimumWidth: 36; horizontalPadding: Theme.spacingS; backgroundColor: "transparent"; textColor: Theme.surfaceVariantText; onClicked: root.removeDevice(modelData.device_id) }
            }
        }
    }
    StyledText {
        width: parent.width
        visible: root.selectedDevice?.supported === false
        text: "此设备尚未被 Bridge 识别为支持的鼠标，授权不代表获得协议支持"
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: root.selectedDevice?.permission_required === true
        text: "此设备缺少访问权限。复制并运行以下命令，然后拔插设备并重新扫描。规则仅授权此 VID/PID。"
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
    }
    TextEdit {
        width: parent.width
        visible: root.selectedDevice?.permission_required === true && root.permissionCommands.length > 0
        text: root.permissionCommands
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        color: Theme.surfaceText
    }
    DButton {
        visible: root.selectedDevice?.permission_required === true && root.permissionCommands.length > 0
        text: "复制授权命令"
        iconName: "content_copy"
        onClicked: Quickshell.execDetached(["dms", "cl", "copy", root.permissionCommands])
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
        model: root.discovered.filter(item => !root.saved.some(saved => saved.device_id === item.device_id))
        delegate: Rectangle {
            required property var modelData
            width: parent.width
            implicitHeight: candidateRow.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            RowLayout {
                id: candidateRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM
                DIcon { name: modelData.supported ? "mouse" : "usb"; size: 24; color: Theme.surfaceVariantText }
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; color: Theme.surfaceText }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.vendor_id + ":" + modelData.product_id + " · " + (modelData.supported ? (modelData.permission_required ? "需要授权" : "可连接") : "暂不支持")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                DButton { text: "添加"; iconName: "add"; onClicked: root.add(modelData) }
            }
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
                    root.scanMessage = reply.result.length ? "选择要添加的设备" : "未发现 USB HID 设备，请检查连接";
                } catch (error) { root.scanMessage = "扫描失败：" + error.message; }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.scanMessage = "扫描进程失败：" + exitCode; }
    }
}
