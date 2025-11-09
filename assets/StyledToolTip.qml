import QtQuick 2.0
import QtQuick.Controls 2.0
import Qt.labs.settings 1.0

ToolTip {
    id: root
    delay: 1000
	timeout: 5000
	visible: settings.showToolTips && parent.hovered
    contentItem: StyledLabel {text: root.text}
    background: Rectangle {
		radius: sizes.minSpacing
		color: colors.midBlue
		border {
			width: sizes.thinBorderWidth
			color: colors.whiteText
		}
	}
	ColorPalette {id: colors}
	SizePalette {id: sizes}
	Settings {
		id: settings
		category: "MuseLab"
	}
}
