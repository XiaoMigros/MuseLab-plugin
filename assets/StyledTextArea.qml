import QtQuick 2.0
import QtQuick.Controls 2.0

TextArea {
	id: control
	property bool accented: true
	background: Rectangle {
		radius: sizes.minSpacing
		color: control.accented ? colors.whiteText : "transparent"
		border {
			color: control.activeFocus ? colors.lightGreen : (control.accented ? colors.midGreen : colors.darkGreen)
			width: sizes.borderWidth
		}
	}
	wrapMode: Text.WordWrap
	font {
		bold: !accented && text != ""
		italic: text == ""
		pointSize: fontSizes.regular
	}
	color: accented ? colors.darkBlue : ((text == "") ? colors.darkGreen : colors.whiteText)
	ColorPalette {id: colors}
	FontSizePalette {id: fontSizes}
	SizePalette {id: sizes}
}
