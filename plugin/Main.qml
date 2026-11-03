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
    popoutWidth: 400
    popoutHeight: Math.max(240, detailsHeight + 60)
    property real detailsHeight: 180
    popoutContent: Component {
        PopoutComponent {
            id: details
            property bool showError: false
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
                    font.pixelSize: mouse.status ? 32 : Theme.fontSizeMedium
                }
                StyledText {
                    width: parent.width
                    visible: mouse.message.length > 0
                    wrapMode: Text.Wrap
                    text: mouse.status ? "刷新失败 · 上次更新 " + mouse.lastSuccess : (mouse.selectedDeviceId ? "暂时无法读取设备，请重试" : "请在设置中添加设备")
                    color: Theme.surfaceVariantText
                    Accessible.role: Accessible.StaticText
                }
                DButton {
                    visible: mouse.message.length > 0 && mouse.selectedDeviceId.length > 0
                    text: details.showError ? "收起错误详情" : "查看错误详情"
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: details.showError = !details.showError
                }
                StyledText {
                    width: parent.width
                    visible: details.showError && mouse.message.length > 0
                    text: mouse.message
                    wrapMode: Text.Wrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
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
