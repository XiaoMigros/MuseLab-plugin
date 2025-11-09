import QtQuick 2.0

IconButton {
	anchors {
		right: parent.right
		verticalCenter: parent.verticalCenter
	}
	opacity: enabled ? 1.0 : colors.disabledOpacity
	height: parent.height
	imgSource: "icons/close.svg"
	ColorPalette {id: colors}
}
