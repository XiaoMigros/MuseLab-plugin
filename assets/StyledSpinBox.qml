import QtQuick 2.0
import QtQuick.Controls 2.2

SpinBox {
	id: control
	editable: true
	implicitWidth: sizes.buttonWidth
	implicitHeight: sizes.controlHeight
	property bool accented: true
	property int indicatorWidth: Math.round(sizes.buttonWidth / 4)
	leftPadding: sizes.borderWidth
	rightPadding: sizes.borderWidth
	topPadding: sizes.borderWidth
	bottomPadding: sizes.borderWidth
	onValueChanged: spinText.text = textFromValue(value, locale)
	
	contentItem: Item {}
	
	StyledTextField {
		z: 2
		id: spinText
		anchors {
			left: parent.left
			leftMargin: control.leftPadding
			verticalCenter: parent.verticalCenter
			rightMargin: control.indicatorWidth + control.rightPadding
			right: parent.right
		}
		//implicitWidth: contentWidth + leftPadding + rightPadding
		topPadding: Math.round((height - contentHeight) / 2)
		text: control.textFromValue(control.value, control.locale)
		accented: parent.accented
		background: Rectangle {color: "transparent"}

		font.bold: false
		onTextEdited: if (text != "") control.value = control.valueFromText(text, control.locale)
		
		readOnly: !control.editable
		validator: control.validator
		inputMethodHints: Qt.ImhFormattedNumbersOnly
	}
	up.indicator: Item {
		z: 1
		enabled: control.value < control.to
		anchors {
			top: parent.top
			topMargin: control.topPadding
			right: parent.right
			rightMargin: control.rightPadding
			bottom: parent.verticalCenter
		}
		width: control.indicatorWidth
		
		Rectangle {
			z: -1
			anchors.fill: parent
			color: enabled ? (!control.accented ? (control.up.hovered ? colors.darkGreen : (control.up.pressed ? colors.midBlue : colors.darkBlue)) : 
				(control.up.hovered ? colors.midGreen : (control.up.pressed ? colors.lightGreen : "transparent"))) : "transparent"
			opacity: control.up.pressed ? 1.0 : colors.styledOpacity
		}
		StyledIcon {
			source: "icons/downarrow.svg"
			rotation: 180
			height: Math.round(1/6 * sizes.controlHeight)
			opacity: enabled ? 1.0 : colors.disabledOpacity
			color: control.accented ? (enabled ? colors.darkBlue : colors.midBlue) : colors.whiteText
		}
	}
	down.indicator: Item {
		z: 1
		enabled: control.value > control.from
		anchors {
			bottom: parent.bottom
			bottomMargin: control.bottomPadding
			right: parent.right
			rightMargin: control.rightPadding
			top: parent.verticalCenter
		}
		width: control.indicatorWidth
		
		Rectangle {
			z: -1
			anchors.fill: parent
			color: enabled ? (!control.accented ? (control.down.hovered ? colors.darkGreen : (control.down.pressed ? colors.midBlue : colors.darkBlue)) : 
				(control.down.hovered ? colors.midGreen : (control.down.pressed ? colors.lightGreen : "transparent"))) : "transparent"
			opacity: control.down.pressed ? 1.0 : colors.styledOpacity
		}
		StyledIcon {
			source: "icons/downarrow.svg"
			height: Math.round(1/6 * sizes.controlHeight)
			opacity: enabled ? 1.0 : colors.disabledOpacity
			color: control.accented ? (enabled ? colors.darkBlue : colors.midBlue) : colors.whiteText
		}
	}
	background: Rectangle {
		anchors.fill: parent
		radius: sizes.minSpacing
		color: control.accented ? colors.whiteText : "transparent"
		border {
			color: control.activeFocus ? colors.lightGreen : (control.accented ? colors.midGreen : colors.darkGreen)
			width: sizes.borderWidth
		}
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
