import QtQuick 2.0
import QtQuick.Controls 2.0

AbstractButton {
	id: root
	implicitWidth: Math.max(label.implicitWidth + (2 * sizes.regSpacing), sizes.buttonWidth)
	implicitHeight: Math.max(label.implicitHeight + (2 * sizes.minSpacing), sizes.controlHeight)
	property bool accentButton: true
	background: Rectangle {
		color: root.accentButton ? (root.hovered ? colors.darkGreen : colors.lightGreen) : (root.hovered ? colors.midGreen : "transparent") //"#14b8a61a"
		border {
			color: (root.activeFocus && !root.hovered) ? colors.whiteText : colors.midGreen //""#14b8a6" ""#14b8a61a"
			width: sizes.borderWidth
		}
		radius: sizes.minSpacing
	}
	contentItem: StyledLabel {
		id: label
		color: root.accentButton ? colors.whiteText : (root.hovered ? colors.whiteText : colors.greenText)
		text: parent.text
		anchors.centerIn: root
		horizontalAlignment: Qt.AlignHCenter
		verticalAlignment: Qt.AlignVCenter
		elide: Text.ElideRight
	}
	opacity: enabled ? 1.0 : colors.disabledOpacity
	Keys.onReturnPressed: clicked()
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
