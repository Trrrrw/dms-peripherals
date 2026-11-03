import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    readonly property var shownDevices: (pluginData.devices || []).filter(device => device.showInBar !== false)
    readonly property var configuredDevices: pluginData.devices || []
    property string workspaceTab: "概览"
    function openWithMode(mode) {
        const names = {overview:"概览",performance:"性能",buttons:"按键",advanced:"高级"};
        workspaceTab = names[mode] || "概览";
        if (!interactionActive) triggerPopout();
    }
    property string activeDeviceId: ""
    readonly property var activeDevice: configuredDevices.find(device => device.device_id === activeDeviceId) || configuredDevices[0] || null
    readonly property var activeReader: activeDevice ? readers[activeDevice.device_id] || null : null
    property bool detailsRequested: false
    function openDevice(deviceId) {
        activeDeviceId = deviceId;
        detailsRequested = false;
        if (!interactionActive) triggerPopout();
    }
    onActiveDeviceChanged: detailsRequested = false
    onInteractionActiveChanged: if (interactionActive) detailsRequested = false
    Timer {
        interval: 250
        repeat: true
        running: root.interactionActive && !root.detailsRequested
        onTriggered: {
            if (root.activeReader && !root.activeReader.busy) {
                root.detailsRequested = true;
                root.activeReader.readDetails();
            }
        }
    }
    property var readers: ({})
    property real detailsHeight: 180

    function battery(device) {
        const status = readers[device.device_id]?.status;
        return status ? status.battery_percent + "%" : "—";
    }

    Repeater {
        model: root.configuredDevices
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
                delegate: Item {
                    required property var modelData
                    implicitWidth: pillRow.implicitWidth
                    implicitHeight: pillRow.implicitHeight
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openDevice(parent.modelData.device_id) }
                    Row {
                    id: pillRow
                    spacing: Theme.spacingXS
                    DIcon { name: parent.parent.modelData.icon || "mouse"; size: root.iconSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: root.battery(parent.parent.modelData); font.pixelSize: root.textSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                    }
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
                delegate: Item {
                    required property var modelData
                    implicitWidth: pillColumn.implicitWidth
                    implicitHeight: pillColumn.implicitHeight
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openDevice(parent.modelData.device_id) }
                    Column {
                    id: pillColumn
                    spacing: Theme.spacingXS
                    DIcon { name: parent.parent.modelData.icon || "mouse"; size: root.iconSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText { text: root.battery(parent.parent.modelData); font.pixelSize: root.textSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
            DIcon { visible: root.shownDevices.length === 0; name: "devices"; size: root.iconSize; color: Theme.surfaceVariantText }
        }
    }
    popoutWidth: 640
    popoutHeight: 650
    popoutContent: Component {
        Item {
            implicitHeight: 590
            Column {
                anchors.fill: parent
                spacing: Theme.spacingM
                DDropdown {
                    id: selector
                    width: parent.width
                    options: root.configuredDevices.map(device => device.name + " · " + device.device_id)
                    currentValue: root.activeDevice ? root.activeDevice.name + " · " + root.activeDevice.device_id : ""
                    enabled: root.configuredDevices.length > 0
                    onValueChanged: value => {
                        const index = options.indexOf(value);
                        if (index >= 0) root.openDevice(root.configuredDevices[index].device_id);
                    }
                }
                Flickable {
                    width: parent.width
                    height: parent.height - selector.height - parent.spacing
                    contentWidth: width
                    contentHeight: panel.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    DevicePanel { id: panel; width: parent.width; device: root.activeDevice; reader: root.activeReader; requestedTab: root.workspaceTab }
                }
            }
        }
    }
}
