import QtQuick 2.0
import QtQuick.Controls 2.0

TabButton {
	id: control
	width: Math.max(contentItem.implicitWidth + (2 * sizes.regSpacing), sizes.buttonWidth)
	height: Math.max(contentItem.implicitHeight + (2 * sizes.minSpacing), sizes.controlHeight)
	background: Rectangle {
		//color: (control.hovered ? colors.darkGreen : "transparent")
		color: parent.hovered ? colors.darkGreen : (parent.checked ? colors.midBlue : colors.darkBlue)
		opacity: (parent.hovered && !parent.checked) ? colors.styledOpacity : 1.0
		//border {
		//	color: control.hovered ? colors.midGreen : (control.checked ? colors.lightGreen : colors.darkGreen)
		//	width:sizes.borderWidth
		//}
		radius: sizes.minSpacing
	}
	contentItem: StyledLabel {
		color: (control.hovered || control.checked) ? colors.whiteText : colors.greenText
		text: parent.text
		anchors.centerIn: control.background
		horizontalAlignment: Qt.AlignHCenter
		verticalAlignment: Qt.AlignVCenter
		elide: Text.ElideRight
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
