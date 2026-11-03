import QtQuick
import qs.Common
import qs.DCommon.Widgets
Rectangle {
    id: root
    property string title: ""
    default property alias content: body.data
    implicitHeight: layout.implicitHeight + Theme.spacingM * 2
    color: Theme.surfaceContainer
    radius: Theme.cornerRadius
    Column {
        id: layout
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingM
        StyledText { visible: root.title.length > 0; text: root.title; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.DemiBold; color: Theme.surfaceText }
        Column { id: body; width: parent.width; spacing: Theme.spacingM }
    }
}
