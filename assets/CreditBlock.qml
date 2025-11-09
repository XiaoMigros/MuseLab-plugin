import QtQuick 2.0
import QtQuick 2.3 as IMG
import QtGraphicalEffects 1.0
import QtQuick.Layouts 1.2

Item {
	id: root
	property string imgsource: ""
	property string title: ""
	property string text: ""
	property bool rightAligned: false
	property int rowSpacing: sizes.buttonWidth
	
	Row {
		width: parent.width
		spacing: root.rowSpacing
		LayoutMirroring.enabled: root.rightAligned
		LayoutMirroring.childrenInherit: true
		
		Circle {
			id: circle
			height: root.height
			anchors.verticalCenter: parent.verticalCenter
			
			IMG.Image {
				source: root.imgsource.replace(/^assets\//g, "")
				anchors.fill: parent
				fillMode: Image.PreserveAspectCrop // ensure it fits, no stretching
				mipmap: true // smoothing, available from QtQuick 2.3
				anchors.centerIn: parent
				layer.enabled: true
				layer.effect: OpacityMask {
					maskSource: parent
				}
			}//Image
		}
		Column {
			clip: true
			spacing: sizes.regSpacing
			width: root.width - root.rowSpacing - circle.width
			height: root.height
			anchors.verticalCenter: parent.verticalCenter
			
			StyledLabel {
				font.pointSize: fontSizes.heading
				text: root.title
				width: parent.width
				elide: Text.ElideRight
			}
			StyledLabel {
				text: root.text
				width: parent.width
				wrapMode: Text.WordWrap
			}
		}
		SizePalette {id: sizes}
		FontSizePalette {id: fontSizes}
	}
}
