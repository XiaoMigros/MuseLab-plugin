import QtQuick 2.0
import QtQuick.Controls 2.0
import QtQuick.Layouts 1.3

Popup {
	id: root
	topPadding: padding + (titleItem.visible ? titleItem.height : 0)
	padding: sizes.regSpacing
	
	x: Math.round((parent.width - width) / 2)
	y: Math.round((parent.height - height) / 2)
	
	property var title: ""
	property var extraHeight: topPadding + padding + (buttons.length > 0 ? sizes.controlHeight : 0)
	property var extraWidth: 2 * padding
	
	background: Rectangle {
		radius: sizes.regSpacing
		color: colors.darkBlue
		border {
			width: sizes.thinBorderWidth
			color: colors.whiteText
		}
	}
	
	Item {
		id: titleItem
		anchors.bottomMargin: root.padding
		height: sizes.controlHeight
		width: root.width
		x: -root.padding; y: -root.topPadding
		visible: root.title != ""
		Rectangle {
			id: titleUpRect
			radius: root.background.radius
			height: Math.min(sizes.controlHeight, 2 * root.background.radius)
			anchors {
				top: parent.top
				left: parent.left
				right: parent.right
			}
			color: colors.whiteText
		}
		Rectangle {
			id: titleDownRect
			color: titleUpRect.color
			anchors {
				top: titleUpRect.verticalCenter
				left: parent.left
				right: parent.right
				bottom: parent.bottom
			}
		}
		StyledLabel {
			text: root.title
			anchors.centerIn: parent
			color: colors.darkBlue
		}
	}
	
	signal accepted
	signal rejected
	property var buttons: [qsTr("OK"), qsTr("Cancel")]
	//storing functions directly in the model doesnt work
	function actions (index) {
		switch (index) {
			case 0: return root.accepted()
			case 1: return root.rejected()
		}
	}
	
	property alias buttonsRow: buttonsRow
	
	RowLayout {
		id: buttonsRow
		anchors {
			right: parent.right
			bottom: parent.bottom
			//margins: sizes.regSpacing
		}
		spacing: sizes.regSpacing
		layoutDirection: Qt.RightToLeft
		
		Repeater {
			id: repeater
			model: root.buttons
			
			StyledButton {
				text: repeater.model[index]
				onClicked: root.actions(index)
			}
		}
	}
	
	onRejected: root.close()
	
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
