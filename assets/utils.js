function isEven(integer) {
	return 2 * Math.round(integer / 2) == integer
}
function formatProjectDate(dateString) {
	return Qt.formatDateTime(new Date(Date.parse(dateString)), "dd MMM yyyy hh:mm")
}
