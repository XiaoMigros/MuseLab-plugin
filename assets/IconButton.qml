import QtQuick 2.0
import QtQuick.Controls 2.0

AbstractButton {
	id: root
	height: 2 * Math.floor((sizes.controlHeight - sizes.minSpacing) / 2)
	width: height
	property int imgPadding: 6
	property var imgSource
	indicator: StyledIcon {
		source: parent.imgSource
		height: parent.height - 2 * parent.imgPadding
		width: parent.width - 2 * parent.imgPadding
	}
	background: Rectangle {
		anchors.centerIn: parent
		height: parent.height - parent.imgPadding
		width: parent.width - parent.imgPadding
		color: ((parent.checkable && parent.checked) || parent.hovered) ? colors.lightGreen : "transparent"
		opacity: colors.styledOpacity
		radius: parent.imgPadding / 2
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
