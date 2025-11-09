import QtQuick 2.3
import QtGraphicalEffects 1.0

Image {
	fillMode: Image.PreserveAspectFit // ensure it fits
	mipmap: true // smoothing
	anchors.centerIn: parent
	property var color: colors.whiteText
	ColorOverlay {
		anchors.fill: parent
		source: parent
		//cached: true
		color: parent.color
	}
	ColorPalette {id: colors}
}
