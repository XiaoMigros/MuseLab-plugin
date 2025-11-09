import QtQuick 2.0
import "utils.js" as Utils

StyledTile {
	color: Utils.isEven(index) ? colors.midBlue : "transparent"
	ColorPalette {id: colors}
}
