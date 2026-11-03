import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
Column {
    id: root
    property var reader: null
    property var device: null
    readonly property var deviceState: reader?.details?.status || ({})
    readonly property var caps: reader?.details?.capabilities || ({})
    readonly property var options: reader?.details?.options || ({})
    property string tab: "概览"
    property string requestedTab: "概览"
    onRequestedTabChanged: tab = requestedTab
    property bool showDiagnostic: false
    property bool showError: false
    property bool detailAttempted: false
    onReaderChanged: detailAttempted = false
    Timer {
        interval: 300
        repeat: true
        running: root.visible && !!root.reader && !root.detailAttempted
        onTriggered: {
            if (!root.reader.busy) {
                root.detailAttempted = true;
                root.reader.readDetails();
            }
        }
    }
    readonly property var tabs: deviceState.debounceMs != null ? ["概览", "性能", "按键", "高级"] : ["概览", "性能", "高级"]
    spacing: Theme.spacingM
    onDeviceChanged: { tab = "概览"; showError = false; }
    readonly property var dpiValues: options.dpi || []
    function dpiIndex(value) {
        if (!dpiValues.length) return 0;
        let closest = 0;
        for (let i = 1; i < dpiValues.length; i++)
            if (Math.abs(dpiValues[i] - value) < Math.abs(dpiValues[closest] - value)) closest = i;
        return closest;
    }
    function write(key, value) { reader?.setSetting(key, value); }

    RowLayout {
        width: parent.width
        DIcon { name: root.device?.icon || "mouse"; size: 32; color: Theme.primary }
        ColumnLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: root.deviceState.name || root.device?.name || "设备"; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeLarge; color: Theme.surfaceText }
            StyledText { text: root.deviceState.connectionDetail || (root.reader?.status ? "已有设备读数" : "等待设备响应"); color: Theme.surfaceVariantText }
        }
        DButton { text: root.reader?.busy ? "读取中…" : "刷新"; iconName: "refresh"; enabled: !!root.reader && !root.reader.busy; onClicked: root.reader.readDetails() }
    }
    DButtonGroup { model: root.tabs; currentIndex: root.tabs.indexOf(root.tab); onSelectionChanged: (index, selected) => { if (selected) root.tab = root.tabs[index]; } }
    StyledText { width: parent.width; visible: !!root.reader?.operationMessage; text: root.reader?.operationMessage || ""; wrapMode: Text.Wrap; color: Theme.primary; Accessible.role: Accessible.StaticText }
    Column {
        width: parent.width
        visible: !!root.reader?.message
        spacing: Theme.spacingXS
        StyledText { width: parent.width; text: root.reader?.status ? "显示历史数据 · " + root.reader.lastSuccess : "无法读取设备，请唤醒设备后重试"; wrapMode: Text.Wrap; color: Theme.surfaceVariantText }
        DButton { text: root.showError ? "收起错误详情" : "查看错误详情"; backgroundColor: "transparent"; textColor: Theme.primary; onClicked: root.showError = !root.showError }
        StyledText { width: parent.width; visible: root.showError; text: root.reader?.message || ""; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
    }

    ControlCard {
        width: parent.width
        visible: root.tab === "概览"
        title: "当前设置"
        RowLayout {
            width: parent.width
            Repeater {
                model: [
                    {label: "灵敏度", value: (root.deviceState.dpi ?? root.reader?.status?.dpi ?? "—") + " DPI"},
                    {label: "回报率", value: (root.deviceState.pollingRateHz ?? root.reader?.status?.polling_rate_hz ?? "—") + " Hz"},
                    {label: "电量", value: (root.deviceState.batteryPercent ?? root.reader?.status?.battery_percent ?? "—") + "%"}
                ]
                delegate: Column {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    StyledText { text: modelData.label; color: Theme.surfaceVariantText }
                    StyledText { text: modelData.value; font.pixelSize: 24; color: Theme.surfaceText }
                }
            }
        }
        StyledText { visible: root.deviceState.batteryState != null; text: root.deviceState.batteryState === "Charging" ? "正在充电" : "放电中"; color: Theme.surfaceVariantText }
        Flow {
            width: parent.width
            spacing: Theme.spacingS
            Repeater {
                model: root.deviceState.dpiStages || []
                delegate: DButton {
                    required property int index
                    required property var modelData
                    text: String(modelData)
                    iconName: root.deviceState.activeDpiStage === index ? "radio_button_checked" : "radio_button_unchecked"
                    minimumWidth: 100
                    maximumWidth: 100
                    enabled: !!root.caps.activeDpiStage && !root.reader?.busy
                    onClicked: root.write("activeDpiStage", index)
                }
            }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "概览"
        title: "电量变化 · 最近 7 天"
        Canvas {
            id: batteryChart
            width: parent.width
            height: 110
            property var points: root.reader?.history || []
            property color lineColor: Theme.primary
            onPointsChanged: requestPaint()
            onLineColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (points.length < 2) return;
                const start = points[0].time, span = Math.max(1, points[points.length - 1].time - start);
                ctx.beginPath();
                for (let i = 0; i < points.length; i++) {
                    const x = 2 + (points[i].time - start) / span * (width - 4);
                    const y = 4 + (100 - points[i].percent) / 100 * (height - 8);
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.strokeStyle = lineColor;
                ctx.lineWidth = 2;
                ctx.stroke();
            }
            StyledText { anchors.centerIn: parent; visible: batteryChart.points.length < 2; text: "正在积累电量记录"; color: Theme.surfaceVariantText }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "概览"
        title: "固件"
        StyledText { text: (root.deviceState.firmware || []).join(" · ") || "未提供版本信息"; color: Theme.surfaceText }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "性能"
        title: "灵敏度"
        Repeater {
            model: root.deviceState.dpiStages || []
            delegate: RowLayout {
                id: stageRow
                required property int index
                required property var modelData
                width: parent.width
                DButton {
                    iconName: root.deviceState.activeDpiStage === index ? "radio_button_checked" : "radio_button_unchecked"
                    tooltipText: "选择档位 " + (stageRow.index + 1)
                    Layout.minimumWidth: 36
                    Layout.preferredWidth: 36
                    Layout.maximumWidth: 36
                    minimumWidth: 36
                    maximumWidth: 36
                    horizontalPadding: Theme.spacingXS
                    enabled: !!root.caps.activeDpiStage && !root.reader?.busy
                    onClicked: root.write("activeDpiStage", index)
                }
                DTextField { id: stageValue; Layout.preferredWidth: 90; text: String(modelData); validator: IntValidator { bottom: 1; top: 100000 } }
                DSlider {
                    id: stageSlider
                    Layout.fillWidth: true
                    minimum: 0
                    maximum: Math.max(0, root.dpiValues.length - 1)
                    step: 1
                    value: root.dpiIndex(stageRow.modelData)
                    showValue: false
                    enabled: !!root.caps.dpiStages && !root.reader?.busy && root.dpiValues.length > 1
                    Accessible.name: "档位 " + (stageRow.index + 1) + " DPI"
                    onSliderValueChanged: newValue => stageValue.text = String(root.dpiValues[newValue])
                    onSliderDragFinished: finalValue => {
                        if (root.dpiValues[finalValue] !== stageRow.modelData)
                            root.write("dpiStages", {index:stageRow.index, dpi:root.dpiValues[finalValue]});
                        value = Qt.binding(() => root.dpiIndex(stageRow.modelData));
                    }
                }
                DButton { text: "保存"; enabled: !!root.caps.dpiStages && !root.reader?.busy && stageValue.text.length > 0 && Number(stageValue.text) !== modelData; onClicked: root.write("dpiStages", {index:index, dpi:Number(stageValue.text)}) }
            }
        }
        RowLayout {
            width: parent.width
            DTextField { id: dpi; Layout.fillWidth: true; placeholderText: "自定义 DPI"; validator: IntValidator { bottom: 1; top: 100000 } }
            DButton { text: "应用"; enabled: !!root.caps.dpi && !root.reader?.busy && dpi.text.length > 0; onClicked: root.write("dpi", Number(dpi.text)) }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "性能"
        title: "回报率"
        Flow {
            width: parent.width
            spacing: Theme.spacingS
            Repeater {
                model: root.options.pollingRateHz || root.deviceState.supportedPollingRates || []
                delegate: DButton {
                    required property var modelData
                    text: modelData + " Hz"
                    iconName: root.deviceState.pollingRateHz === modelData ? "radio_button_checked" : "radio_button_unchecked"
                    minimumWidth: 120
                    maximumWidth: 120
                    enabled: !!root.caps.pollingRateHz && !root.reader?.busy
                    onClicked: root.write("pollingRateHz", modelData)
                }
            }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "性能" && root.deviceState.liftOffDistance != null
        title: "抬起高度"
        DButtonGroup {
            property var values: root.deviceState.supportedLiftOffDistances || ["Low", "High"]
            model: values.map(value => value === "Low" ? "低" : value === "High" ? "高" : "中")
            currentIndex: values.indexOf(root.deviceState.liftOffDistance)
            enabled: !!root.caps.liftOffDistance && !root.reader?.busy
            onSelectionChanged: (index, selected) => { if (selected) root.write("liftOffDistance", values[index]); }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "性能" && (root.deviceState.motionSync != null || root.deviceState.angleSnapping != null || root.deviceState.rippleControl != null)
        title: "信号处理"
        Repeater {
            model: [{key:"motionSync",label:"运动同步"},{key:"angleSnapping",label:"直线修正"},{key:"rippleControl",label:"Ripple control"}]
            delegate: RowLayout {
                required property var modelData
                width: parent.width
                visible: root.deviceState[modelData.key] != null
                StyledText { Layout.fillWidth: true; text: modelData.label; color: Theme.surfaceText }
                DToggle { id: processingToggle; checked: root.deviceState[modelData.key] === true; enabled: !!root.caps[modelData.key] && !root.reader?.busy; onToggled: checked => { root.write(modelData.key, checked); processingToggle.checked = Qt.binding(() => root.deviceState[modelData.key] === true); } }
            }
        }
        StyledText { visible: root.deviceState.angleTuning != null; text: "角度微调  " + root.deviceState.angleTuning + "°（当前驱动只读）"; color: Theme.surfaceVariantText }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "按键"
        title: "防抖"
        DDropdown {
            width: parent.width
            options: (root.options.debounceMs || []).map(value => value + " ms")
            currentValue: root.deviceState.debounceMs + " ms"
            enabled: !!root.caps.debounceMs && !root.reader?.busy
            onValueChanged: value => { root.write("debounceMs", parseInt(value)); currentValue = Qt.binding(() => root.deviceState.debounceMs + " ms"); }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "高级" && root.deviceState.sleepTimeout != null
        title: "自动休眠"
        DDropdown {
            width: parent.width
            options: (root.options.sleepTimeout || []).map(value => value + " 秒")
            currentValue: root.deviceState.sleepTimeout + " 秒"
            enabled: !!root.caps.sleepTimeout && !root.reader?.busy
            onValueChanged: value => { root.write("sleepTimeout", parseInt(value)); currentValue = Qt.binding(() => root.deviceState.sleepTimeout + " 秒"); }
        }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "高级" && !!root.deviceState.atkReceiver
        title: "接收器"
        StyledText { text: root.deviceState.atkReceiver?.online ? "鼠标在线" : "鼠标离线"; color: Theme.surfaceText }
        StyledText { text: "射频标识符  " + (root.deviceState.atkReceiver?.rfId || "—"); color: Theme.surfaceVariantText }
        StyledText { text: "配对状态  " + (root.deviceState.atkReceiver?.pairingStatus ?? "—"); color: Theme.surfaceVariantText }
    }
    ControlCard {
        width: parent.width
        visible: root.tab === "高级"
        title: "诊断"
        DButton { text: root.showDiagnostic ? "收起诊断信息" : "查看诊断信息"; backgroundColor: "transparent"; textColor: Theme.primary; onClicked: root.showDiagnostic = !root.showDiagnostic }
        TextEdit {
            width: parent.width
            visible: root.showDiagnostic
            text: JSON.stringify({status: root.deviceState, capabilities: root.caps}, null, 2)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
    }

}
