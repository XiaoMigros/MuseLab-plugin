import QtQuick 2.0
import QtQuick.Controls 2.0
import "utils.js" as Utils

ComboBox {
	id: root
	implicitWidth: 120
	implicitHeight: sizes.controlHeight
	opacity: enabled ? 1.0 : colors.disabledOpacity
	property int displayBeforeClip: 6
	property int popupItemHeight: implicitHeight
	property int popupItemWidth: implicitWidth
	property bool rightAligned: false
	clip: true
	
	delegate: ItemDelegate {
		width: root.popupItemWidth
		height: root.popupItemHeight
		contentItem: StyledLabel {
			font.bold: false
			property var textRole: root.textRole
			text: root.model[index][textRole]
			elide: Text.ElideRight
			verticalAlignment: Text.AlignVCenter
		}
		background: Rectangle {
			//color: parent.hovered ? colors.darkGreen : colors.midGreen
			//anchors.fill: parent
			radius: parent.hovered ? sizes.minSpacing : 0
			//opacity: 0.7
			color: parent.hovered ? colors.darkGreen : (Utils.isEven(index) ? colors.midBlue : "transparent")
		}
	}
	background: Rectangle {
		color: parent.hovered ? colors.darkGreen : colors.lightGreen
		border {
			color: colors.midGreen
			width: sizes.borderWidth
		}
		radius: sizes.minSpacing
	}
	contentItem: StyledLabel {
		text: root.currentText
		anchors {
			verticalCenter: parent.verticalCenter
			left: parent.left
			leftMargin: sizes.regSpacing
		}
		verticalAlignment: Text.AlignVCenter
		width: root.width - (anchors.leftMargin + root.indicator.width + 2 * root.indicator.anchors.margins)
		elide: Text.ElideRight
	}
	indicator: Item {
		width: 2 * sizes.regSpacing
		height: sizes.regSpacing
		anchors {
			verticalCenter: parent.verticalCenter
			right: parent.right
			margins: sizes.minSpacing
		}
		StyledIcon {
			anchors.fill: parent
			source: "icons/downarrow.svg"
		}
	}
	popup: Popup {
		y: root.height
		x: root.rightAligned ? (root.width - root.popupItemWidth) : 0
		width: root.popupItemWidth
		implicitHeight: contentItem.implicitHeight
		padding: sizes.thinBorderWidth

		contentItem: ListView {
			clip: true
			implicitHeight: root.popupItemHeight * Math.min(root.displayBeforeClip, root.count) //contentHeight
			model: root.popup.visible ? root.delegateModel : null
			currentIndex: root.highlightedIndex

			ScrollIndicator.vertical: ScrollIndicator {visible: root.displayBeforeClip < root.model.length}
		}

		background: Rectangle {
			color: colors.darkBlue
			border.color: colors.whiteText
			radius: sizes.minSpacing
		}
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
