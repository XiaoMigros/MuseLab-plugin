import QtQuick 2.0

Item {
	property var radius: sizes.minSpacing
	property var color: colors.midBlue
	
	Rectangle {
		z: -1
		anchors.fill: parent
		radius: parent.radius
		opacity: colors.styledOpacity
		color: parent.color
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}

