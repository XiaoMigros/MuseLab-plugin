import QtQuick 2.0
import QtQuick.Controls 2.2

CheckBox {
	id: root
	indicator: Rectangle {
		id: box
		implicitWidth: 2 * sizes.regSpacing
		implicitHeight: implicitWidth
		x: root.leftPadding
		y: root.height / 2 - height / 2
		color: colors.whiteText
		radius: sizes.minSpacing - sizes.borderWidth
		//border.width: (root.activeFocus && !root.down) ? 2 : 0
		//border.color: colors.lightGreen

		Item {
			id: mainContainer
			anchors {
				top: parent.top
				right: parent.right
			}
			width: Math.ceil(box.implicitWidth - (sizes.minSpacing / 2))
			height: Math.ceil(box.implicitHeight - (sizes.minSpacing / 2))
			
			Canvas {
				id: drawingCanvas
				anchors.fill: parent
				visible: root.checked
				onPaint: {
					var ctx = getContext("2d")
					ctx.lineWidth = Math.max(1.5, box.implicitWidth * 0.05)
					ctx.strokeStyle = colors.black
					ctx.beginPath()
					ctx.moveTo(0 + ctx.lineWidth, drawingCanvas.height * (2/3))
					ctx.lineTo(drawingCanvas.width / 3, drawingCanvas.height - ctx.lineWidth)
					ctx.lineTo(drawingCanvas.width - ctx.lineWidth, drawingCanvas.height * (1/3))
					ctx.stroke()
				}
			}
		}
	}
	contentItem: StyledLabel {
		text: root.text
		font.bold: false
		verticalAlignment: Text.AlignVCenter
		leftPadding: root.indicator.width + root.spacing
	}
	Keys.onReturnPressed: clicked()
	ColorPalette {id: colors}
	SizePalette {id: sizes}
}
