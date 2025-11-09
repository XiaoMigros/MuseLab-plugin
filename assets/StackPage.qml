import QtQuick 2.0
import QtQuick.Controls 2.0

Item {
	id: page
	visible: parent.currentItem == page || StackView.status == StackView.Deactivating
	
	signal reload
	
	property var topSpace:		(1/20) * height
	property var bottomSpace:	sizes.regSpacing
	property var leftSpace:		sizes.regSpacing
	property var rightSpace:	sizes.regSpacing
	property var optionWidth:	sizes.optionWidth
	property var maxSpace:		sizes.maxSpacing
	property var regSpace:		sizes.regSpacing
	
	SizePalette {id: sizes}
}
