import QtQuick 2.0
import QtQuick.Controls 2.0

TextField {
	id: control
	property bool accented: true
	implicitWidth: 200
	implicitHeight: sizes.controlHeight
	property bool visibleCursor: false

	background: Rectangle {
		radius: sizes.minSpacing
		color: control.accented ? colors.whiteText : "transparent"
		border {
			color: control.activeFocus ? colors.lightGreen : (control.accented ? colors.midGreen : colors.darkGreen)
			width: sizes.borderWidth
		}
	}
	cursorDelegate: Rectangle {
		visible: control.visibleCursor && control.cursorVisible
		color: control.accented ? colors.darkBlue : colors.whiteText
		width: control.cursorRectangle.width
	}
	Timer {
		id: cursorTimer
		repeat: true
		interval: 500
		onTriggered: control.visibleCursor = !control.visibleCursor
	}
	onFocusChanged: {
		if (focus) resetCursor()
		else cursorTimer.stop()
	}
	onCursorPositionChanged: resetCursor()
	signal resetCursor
	onResetCursor: {
		control.visibleCursor = true
		cursorTimer.restart()
	}
	font {
		bold: !accented && text != ""
		italic: text == ""
		pointSize: fontSizes.regular
	}
	color: accented ? colors.darkBlue : ((text == "") ? colors.darkGreen : colors.whiteText)
	selectionColor: accented ? colors.lightBlue : "transparent"
	selectedTextColor: accented ? colors.whiteText : colors.greenText
	ColorPalette {id: colors}
	FontSizePalette {id: fontSizes}
	SizePalette {id: sizes}
}
