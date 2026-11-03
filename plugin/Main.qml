import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    MouseService {
        id: mouse
        stateStore: root.pluginService
        selectedDeviceId: root.pluginData.selectedDeviceId || ""
        backendPath: root.pluginService ? root.pluginService.getPluginPath(root.pluginId) + "/bin/dms-openmouse" : ""
    }
    readonly property string batteryText: mouse.status ? mouse.status.battery_percent + "%" : "—"
    readonly property color statusColor: mouse.status && mouse.status.battery_percent <= 20 ? Theme.error : Theme.surfaceText

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DIcon {
                name: mouse.status?.charging ? "battery_charging_full" : "mouse"
                size: root.iconSize
                color: root.statusColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.batteryText
                font.pixelSize: root.textSize
                color: root.statusColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DIcon {
                name: "mouse"
                size: root.iconSize
                color: root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.batteryText
                font.pixelSize: root.textSize
                color: root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    popoutWidth: 360
    popoutHeight: Math.max(240, detailsHeight + 60)
    property real detailsHeight: 180
    popoutContent: Component {
        PopoutComponent {
            headerText: mouse.status?.reported_name || "OpenMouse"
            headerActions: Component {
                DButton {
                    text: mouse.busy ? "刷新中…" : "刷新"
                    iconName: "refresh"
                    enabled: !mouse.busy
                    onClicked: mouse.refresh()
                }
            }
            onImplicitHeightChanged: root.detailsHeight = implicitHeight
            Component.onCompleted: root.detailsHeight = implicitHeight
            Column {
                width: parent.width
                spacing: Theme.spacingM
                StyledText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: mouse.status ? root.batteryText + (mouse.status.charging ? " · 正在充电" : "") : "暂无设备数据"
                    color: root.statusColor
                }
                StyledText {
                    width: parent.width
                    visible: mouse.message.length > 0
                    wrapMode: Text.Wrap
                    text: (mouse.status ? "刷新失败，显示上次成功数据（" + mouse.lastSuccess + "）\n" : "读取失败\n") + mouse.message
                    color: Theme.error
                }
                StyledText {
                    visible: !!mouse.status
                    text: "DPI    " + (mouse.status?.dpi ?? "—")
                    color: Theme.surfaceText
                }
                StyledText {
                    visible: !!mouse.status
                    text: "回报率    " + (mouse.status?.polling_rate_hz == null ? "—" : mouse.status.polling_rate_hz + " Hz")
                    color: Theme.surfaceText
                }
            }
        }
    }
}
