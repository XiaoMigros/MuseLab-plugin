import QtQuick 2.0
import QtQuick.Controls 2.0

StyledComboBox {
	indicator: StyledIcon {
		source: "assets/icons/more.svg".replace(/^assets\//g, "")
		height: parent.height - 2 * parent.imgPadding
		width: parent.width - 2 * parent.imgPadding
		anchors.centerIn: parent
	}
	height: sizes.controlHeight
	width: height
	popupItemWidth: 200
	rightAligned: true
	textRole: "text"
	property int imgPadding: 6
	
	contentItem: Item {}
	background: Rectangle {
		anchors.centerIn: parent
		height: sizes.controlHeight - parent.imgPadding
		width: height
		color: (parent.down || parent.hovered) ? colors.lightGreen : "transparent"
		opacity: colors.styledOpacity
		radius: parent.imgPadding / 2
	}
	onActivated: accepted()
	onAccepted: trigger(model[currentIndex].action)
	function trigger(action) {}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}