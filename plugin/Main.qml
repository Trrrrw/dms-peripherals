import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    readonly property var shownDevices: (pluginData.devices || []).filter(device => device.showInBar !== false)
    property var readers: ({})
    property real detailsHeight: 180

    function battery(device) {
        const status = readers[device.device_id]?.status;
        return status ? status.battery_percent + "%" : "—";
    }

    Repeater {
        model: root.shownDevices
        delegate: Item {
            required property var modelData
            property alias reader: service
            MouseService {
                id: service
                stateStore: root.pluginService
                selectedDeviceId: parent.modelData.device_id
                backendPath: root.pluginService ? root.pluginService.getPluginPath(root.pluginId) + "/bin/dms-openmouse" : ""
            }
        }
        onItemAdded: (index, item) => {
            const updated = Object.assign({}, root.readers);
            updated[item.modelData.device_id] = item.reader;
            root.readers = updated;
        }
        onItemRemoved: (index, item) => {
            const updated = Object.assign({}, root.readers);
            delete updated[item.modelData.device_id];
            root.readers = updated;
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingM
            Repeater {
                model: root.shownDevices
                delegate: Row {
                    required property var modelData
                    spacing: Theme.spacingXS
                    DIcon { name: modelData.icon || "mouse"; size: root.iconSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: root.battery(modelData); font.pixelSize: root.textSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            DIcon { visible: root.shownDevices.length === 0; name: "devices"; size: root.iconSize; color: Theme.surfaceVariantText }
        }
    }
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingM
            Repeater {
                model: root.shownDevices
                delegate: Column {
                    required property var modelData
                    spacing: Theme.spacingXS
                    DIcon { name: modelData.icon || "mouse"; size: root.iconSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText { text: root.battery(modelData); font.pixelSize: root.textSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
            DIcon { visible: root.shownDevices.length === 0; name: "devices"; size: root.iconSize; color: Theme.surfaceVariantText }
        }
    }
    popoutWidth: 400
    popoutHeight: Math.max(180, detailsHeight + 60)
    popoutContent: Component {
        PopoutComponent {
            headerText: "OpenMouse"
            onImplicitHeightChanged: root.detailsHeight = implicitHeight
            Component.onCompleted: root.detailsHeight = implicitHeight
            StyledText {
                visible: root.shownDevices.length === 0
                text: "请在设置中添加设备，并开启状态栏显示"
                color: Theme.surfaceVariantText
            }
            Repeater {
                model: root.shownDevices
                delegate: Column {
                    id: deviceDetails
                    required property var modelData
                    readonly property var reader: root.readers[modelData.device_id] || null
                    property bool showError: false
                    width: parent.width
                    spacing: Theme.spacingS
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        DIcon { name: deviceDetails.modelData.icon || "mouse"; size: 24; color: Theme.primary }
                        StyledText { width: parent.width - 130; text: deviceDetails.reader?.status?.reported_name || deviceDetails.modelData.name; elide: Text.ElideRight; color: Theme.surfaceText }
                        DButton { iconName: "refresh"; tooltipText: "刷新设备状态"; minimumWidth: 36; horizontalPadding: Theme.spacingS; enabled: !!deviceDetails.reader && !deviceDetails.reader.busy; onClicked: deviceDetails.reader.refresh() }
                    }
                    StyledText { text: root.battery(deviceDetails.modelData); font.pixelSize: 32; color: Theme.surfaceText }
                    StyledText {
                        width: parent.width
                        visible: !!deviceDetails.reader?.message
                        text: deviceDetails.reader?.status ? "显示历史数据 · " + deviceDetails.reader.lastSuccess : "暂时无法读取设备"
                        wrapMode: Text.Wrap
                        color: Theme.surfaceVariantText
                    }
                    DButton { visible: !!deviceDetails.reader?.message; text: deviceDetails.showError ? "收起错误详情" : "查看错误详情"; backgroundColor: "transparent"; textColor: Theme.primary; onClicked: deviceDetails.showError = !deviceDetails.showError }
                    StyledText { width: parent.width; visible: deviceDetails.showError && !!deviceDetails.reader?.message; text: deviceDetails.reader?.message || ""; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                    StyledText { visible: !!deviceDetails.reader?.status; text: "DPI  " + (deviceDetails.reader?.status?.dpi ?? "—") + "    回报率  " + (deviceDetails.reader?.status?.polling_rate_hz ?? "—") + " Hz"; color: Theme.surfaceText }
                    Item { width: 1; height: Theme.spacingM }
                }
            }
        }
    }
}
