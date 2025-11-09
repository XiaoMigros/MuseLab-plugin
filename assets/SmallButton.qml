import QtQuick 2.0
import QtQuick.Controls 2.0

AbstractButton {
	contentItem: SmallLabel {
		text: parent.text
		font.underline: parent.hovered
	}
}
