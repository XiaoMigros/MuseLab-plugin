import QtQuick 2.0
import QtQuick.Controls 2.0
import "utils.js" as Utils

Flickable {
	id: root
	property var model
	property var actModel
	property var removeEnabled
	signal removeAction(int index)
	property var displayText
	clip: true
	anchors {
		margins: sizes.regSpacing
		left: parent.left
		right: parent.right
		top: parent.top
	}
	ListView {
		id: listView
		anchors.fill: parent
		model: root.actModel
		delegate: AlternatingTile {
			height: sizes.controlHeight
			width: listView.width
			
			StyledLabel {
				font.bold: false
				anchors {
					left: parent.left
					leftMargin: sizes.minSpacing
					verticalCenter: parent.verticalCenter
				}
				text: root.displayText(index)
				width: parent.width - (2 * anchors.leftMargin) - (removeButton.width + removeButton.anchors.rightMargin)
				elide: Text.ElideRight
			}
			ProjectMCloseButton {
				id: removeButton
				enabled: root.removeEnabled(index)
				onClicked: root.removeAction(index)
			}
		}
		ScrollIndicator.vertical: ScrollIndicator {visible: listView.contentHeight > listView.height}
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
