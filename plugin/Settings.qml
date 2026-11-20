import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "peripherals"
    property var discovered: []
    property var saved: loadValue("devices", [])
    property string selected: loadValue("selectedDeviceId", "")
    property string scanMessage: ""
    property string permissionFeedback: ""

    function scanDevices() {
        if (!pluginService || scan.running) return;
        scanMessage = "";
        permissionFeedback = "";
        scan.stdinEnabled = true;
        scan.running = true;
    }

    Timer {
        interval: 50
        running: root.visible && !!root.pluginService
        onTriggered: root.scanDevices()
    }

    readonly property var selectedDevice: discovered.find(item => item.device_id === selected) || saved.find(item => item.device_id === selected) || null
    readonly property string permissionCommands: {
        const device = selectedDevice;
        if (!device || !/^[0-9a-f]{4}$/.test(device.vendor_id || "") || !/^[0-9a-f]{4}$/.test(device.product_id || "")) return "";
        const rule = 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="' + device.vendor_id + '", ATTRS{idProduct}=="' + device.product_id + '", TAG+="uaccess"';
        return "echo '" + rule + "' | sudo tee /etc/udev/rules.d/70-dms-peripherals-" + device.vendor_id + "-" + device.product_id + ".rules\nsudo udevadm control --reload-rules";
    }

    function select(device) {
        selected = device.device_id;
        saveValue("selectedDeviceId", selected);
    }
    function updateDevice(deviceId, values) {
        const updated = saved.map(item => item.device_id === deviceId ? Object.assign({}, item, values) : item);
        saveValue("devices", updated);
        saved = updated;
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
            saved = saved.concat([Object.assign({}, device, {showInBar: true, icon: "mouse"})]);
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
        text: "尚未添加设备，扫描后选择要显示的设备"
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
                DButton {
                    iconName: modelData.icon || "mouse"
                    tooltipText: "切换鼠标／键盘图标"
                    minimumWidth: 36
                    horizontalPadding: Theme.spacingS
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    onClicked: root.updateDevice(modelData.device_id, {icon: modelData.icon === "keyboard" ? "mouse" : "keyboard"})
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; color: Theme.surfaceText }
                    StyledText { text: modelData.showInBar !== false ? "在状态栏显示" : "已隐藏"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
                DButton {
                    iconName: modelData.showInBar !== false ? "visibility" : "visibility_off"
                    tooltipText: modelData.showInBar !== false ? "从状态栏隐藏" : "在状态栏显示"
                    minimumWidth: 36
                    horizontalPadding: Theme.spacingS
                    backgroundColor: "transparent"
                    textColor: modelData.showInBar !== false ? Theme.primary : Theme.surfaceVariantText
                    onClicked: root.updateDevice(modelData.device_id, {showInBar: modelData.showInBar === false})
                }
                DButton { iconName: "admin_panel_settings"; tooltipText: "检查设备权限"; minimumWidth: 36; horizontalPadding: Theme.spacingS; backgroundColor: "transparent"; textColor: Theme.surfaceText; onClicked: root.select(modelData) }
                DButton { iconName: "delete"; tooltipText: "移除设备"; minimumWidth: 36; horizontalPadding: Theme.spacingS; backgroundColor: "transparent"; textColor: Theme.surfaceVariantText; onClicked: root.removeDevice(modelData.device_id) }
            }
        }
    }
    StyledText {
        width: parent.width
        visible: root.selectedDevice?.supported === false
        text: "此设备尚未在支持的驱动列表中，授权不代表获得协议支持"
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: root.selectedDevice?.permission_required === true
        text: "此设备缺少访问权限。复制并运行以下命令。规则仅授权此 VID/PID。"
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: root.selectedDevice?.permission_required === true
        text: "运行命令后，必须拔掉并重新插入设备或接收器，再点击“重新检测”"
        font.weight: Font.DemiBold
        color: Theme.error
        wrapMode: Text.Wrap
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
    RowLayout {
        width: parent.width
        visible: root.selectedDevice?.permission_required === true && root.permissionCommands.length > 0
        spacing: Theme.spacingS
        DButton {
            text: "复制授权命令"
            iconName: "content_copy"
            onClicked: Quickshell.execDetached(["dms", "cl", "copy", root.permissionCommands])
        }
        DButton {
            text: scan.running ? "检测中…" : "重新检测"
            iconName: "refresh"
            enabled: !scan.running
            onClicked: root.scanDevices()
        }
        Item { Layout.fillWidth: true }
    }
    StyledText {
        width: parent.width
        visible: root.permissionFeedback.length > 0
        text: root.permissionFeedback
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
        Accessible.role: Accessible.StaticText
    }
    RowLayout {
        width: parent.width
        StyledText {
            text: "发现设备"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.surfaceText
            Layout.fillWidth: true
        }
        DButton {
            text: scan.running ? "扫描中…" : "重新扫描"
            iconName: "refresh"
            enabled: !scan.running && !!root.pluginService
            onClicked: root.scanDevices()
        }
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
        command: [root.pluginService ? root.pluginService.getPluginPath("peripherals") + "/bin/dms-peripherals" : ""]
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
                    const current = reply.result.find(item => item.device_id === root.selected);
                    if (root.selected) {
                        root.permissionFeedback = !current ? "未检测到所选设备，请确认已重新插入" : current.permission_required ? "仍缺少访问权限，请执行命令并拔插设备后重试" : "访问权限正常";
                    }
                    const updated = root.saved.map(item => Object.assign({}, item, reply.result.find(device => device.device_id === item.device_id) || {}));
                    root.saveValue("devices", updated);
                    root.saved = updated;
                    root.scanMessage = reply.result.length ? "选择要添加的设备" : "未发现 USB HID 设备，请检查连接";
                } catch (error) { root.scanMessage = "扫描失败：" + error.message; }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.scanMessage = "扫描进程失败：" + exitCode; }
    }
}
