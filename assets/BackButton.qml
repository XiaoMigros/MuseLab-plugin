import QtQuick 2.0
import QtQuick.Controls 2.0

SmallButton {
	anchors {
		margins: sizes.regSpacing
		left: parent.left
		bottom: parent.bottom
	}
	text: qsTr("Back")
	onClicked: stackView.pop()
	SizePalette {id: sizes}
}
