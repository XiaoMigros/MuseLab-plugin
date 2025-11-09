import QtQuick 2.0
import QtQuick.Layouts 1.2

Item {
	height: sizes.controlHeight
	property var text: ""
	Layout.fillWidth: true
	StyledTile {radius: sizes.minSpacing}
	StyledLabel {
		id: editProjectCreatedByField
		font.bold: false
		text: parent.text
		anchors {
			left: parent.left
			leftMargin: sizes.minSpacing
			verticalCenter: parent.verticalCenter
		}
		width: parent.width - (2 * anchors.leftMargin)
		elide: Text.ElideRight
	}
	SizePalette {id: sizes}
}
