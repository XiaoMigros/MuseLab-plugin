import QtQuick 2.0
import QtQuick.Controls 1.2

Item {
	property string text: ""
	anchors {
		left: parent.left
		right: parent.right
		top: parent.top
	}
	height: 40
	
	StyledLabel {
		anchors.centerIn: parent
		text: parent.text
		font.pointSize: fontSizes.heading
	}
	FontSizePalette {id: fontSizes}
}
