import QtQuick 2.0
import QtQuick.Controls 1.3
import QtGraphicalEffects 1.0

BusyIndicator {
	ColorOverlay {
		anchors.fill: parent
		source: parent
		//cached: true
		color: colors.whiteText
	}
	ColorPalette {id: colors}
}
