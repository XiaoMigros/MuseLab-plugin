import QtQuick 2.0
import QtQuick.Controls 1.5

StackViewDelegate {
	//function getTransition(properties) {return stackView[properties.name]} WIP
	
	//reset exitItem when animation is finished
	function transitionFinished(properties) {
		properties.exitItem.x = 0
		properties.exitItem.y = 0
	}
	
	popTransition: StackViewTransition {
		PropertyAnimation {
			target: exitItem
			property: "x"
			from: 0
			to: stackView.width
			duration: 1000
			easing.type: Easing.InOutSine
		}
		PropertyAnimation {
			target: enterItem
			property: "x"
			from: (-1) * stackView.width
			to: 0
			duration: 1000
			easing.type: Easing.InOutSine
		}
	}//popTransition
	
	pushTransition: StackViewTransition {
		PropertyAnimation {
			target: enterItem
			property: "x"
			from: stackView.width
			to: 0
			duration: 1000
			easing.type: Easing.InOutSine
		}
		PropertyAnimation {
			target: exitItem
			property: "x"
			from: 0
			to: (-1) * stackView.width
			duration: 1000
			easing.type: Easing.InOutSine
		}
	}//pushTransition
	
	replaceTransition: StackViewTransition {
		PropertyAnimation {
			target: enterItem
			property: "y"
			from: (-1) * stackView.height
			to: 0
			duration: 1000
			easing.type: Easing.InOutSine
		}
		PropertyAnimation {
			target: exitItem
			property: "y"
			from: 0
			to: stackView.height
			duration: 1000
			easing.type: Easing.InOutSine
		}
	}//replaceTransition
}//StackViewDelegate