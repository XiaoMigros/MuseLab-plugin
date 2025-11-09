import QtQuick 2.0
import QtQuick.Controls 2.0

StyledButton {
	property var imgsource
	implicitHeight: sizes.controlHeight
	implicitWidth: 60
	contentItem: StyledIcon {
		anchors {
			fill: parent
			margins: sizes.minSpacing
			centerIn: parent
		}
		source: parent.imgsource.replace(/^assets\//g, "")
	}
	hoverEnabled: true
	StyledToolTip {
		text: qsTr("Add a %1 to the score that automatically syncs with other users").arg(parent.text)
	}
}
