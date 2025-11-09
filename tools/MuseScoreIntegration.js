//keeps track of current element information, to detect when changes are made
var prevState = {
	"ties": {
		"forward": false,
		"back": false
	},
	"visible": true,
	"placement": false,
	"beamMode": 0,
	"offsetY": 0,
	"scoreLength": 0,
	"duration": {
		"numerator": 0,
		"denominator": 0
		"tick": 0
	}
}
//detects changes made to the score and handles them accordingly
function scoreStateChanged(state) {
	try {
		if (root.token != "") {
			if (curScore && curScore.metaTag("project-id") == root.currentProjectId) {
				root.currentProjectOpen = true
				if (!root.busy) {
					if (root.missingLatestChanges) {
						root.getRecentChanges()
						root.missingLatestChanges = false
					}
					if (state.excerptsChanged || state.instrumentsChanged || scoreLengthChanged()) {
						debugLog("Forcing score reload", 1)
						queueChanges({data: [{}], sendScore: true})
					}
					else if (state.selectionChanged || scoreChanged()) { //switch order to be more efficient?
						var sendObjs = []
						for (var i in curScore.selection.elements) {
							var el = curScore.selection.elements[i]
							if (el) {
								//Grace Notes
								if ((el.type == Element.NOTE && el.noteType != NoteType.NORMAL) || (el.type == Element.CHORD && el.notes[0].noteType != NoteType.NORMAL)) {
									el = getChordRestFromGraceNote(el)
								}
								//Dynamics, Tempo Text, Staff/System Text & Fermatas
								if (el.type == Element.DYNAMIC || el.type == Element.TEMPO_TEXT || el.type == Element.STAFF_TEXT || el.type == Element.SYSTEM_TEXT || el.type == Element.FERMATA) {
									el = getChordRestFromAnnotation(el)
									//add these elements if they are selected (reload their chordrest)
								}
								//articulations
								if (el.type == Element.ARTICULATION) {
									el = el.parent
								}
								////Notes, Rests, & Tuplets
								if (el.type == Element.NOTE || el.type == Element.REST || el.type == Element.CHORD || el.type == Element.TUPLET) {
									try {
										var sendObj = {}
										if (el.type == Element.TUPLET || getChordRest(el).tuplet) {
											var tuplet = getMotherTuplet(getChordRest(el))
											sendObj = getTupletObj(tuplet)
										} else {
											sendObj = getChordRestObj(el)
										}
										debugLog(("logging " + sendObj.type + ": Tick " + sendObj.startTick + ", voice " + (sendObj.track % 4 + 1) + ", staff "
											+ Math.ceil((sendObj.track + 1) / 4) + ", duration: " + sendObj.duration.numerator + "/" + sendObj.duration.denominator), 1)
										sendObj.sender = root.userId
										sendObjs.push(sendObj)
									}
									catch(e) {
										debugLog(e, 2)
										logMessage(e)
									}
								}
								//Time Signatures
								var tsCursor = curScore.newCursor()
								tsCursor.rewindToTick(getTick(el))
								tsCursor.filter = Segment.All
								var mtick = tsCursor.measure.firstSegment.tick-1
								while (tsCursor.tick > mtick) {
									var e = tsCursor.element
									if (e && e.type == Element.TIMESIG) {
										var sendObj = {
											duration: {
												numerator: tsCursor.measure.timesigActual.numerator,
												denominator: tsCursor.measure.timesigActual.denominator
											},
											startTick: tsCursor.measure.firstSegment.tick,
											sender: root.userId,
											type: getType(e) //or unknown => to get the score to hardsync
										}
										sendObjs.push(sendObj)
										if (root.logMode) debugLog(("logging " + sendObj.type + ": Tick " + sendObj.startTick + ": "
										+ sendObj.duration.numerator + "/" + sendObj.duration.denominator), 1)
										break
									}//if
									tsCursor.prev()
								}//while
								tsCursor.next()
							}
						}
						root.queueChanges({data: sendObjs, sendScore: false})
					}
				}
			} else {
				root.currentProjectOpen = false
			}
		}
	}
	catch(e) {
		debugLog((e), 2)
	}
	debugLog(("Current project open: " + root.currentProjectOpen), 0)
	debugLog(("Missing latest changes: " + root.missingLatestChanges), 0)
	debugLog(("Making ongoing changes: " + root.busy), 0)
}
//handles initial file opening, and (re)loads changes after saves
function handleSync(score) {
	try {
		if (root.inited) debugLog("Reloading score...", 2)
		else {
			debugLog("Opening score", 2)
			logMessage(root.userName + " has joined project " + root.currentProjectName)
		}
		var resp = root.loadOlderFile ? root.loadOlderFile : LZString.LZString.decompressFromBase64(score)
		if (resp.length < 1) return debugLog("No data, aborting...", 2)

		for (var i in scores) {
			if (curScore.metaTag("project-id") == root.currentProjectId) {
				cmd("file-save")
				closeScore(curScore)
				if (root.inited) break
			} else {
				if (i == 0) cmd("escape")
				cmd("next-score")
			}
		}
		//readScore(tempXMLFile.source, root.inited) //true bypasses save messages
		tempXMLFile.write(resp)
		readScore(tempXMLFile.source, false)
		pluginWindow.raise()
		if (!curScore.metaTag("project-id")) curScore.setMetaTag("project-id", root.currentProjectId)
		root.prevState.scoreLength = getScoreLength()
		root.missingLatestChanges = false
		//updateStaffList()
		if (!root.inited) {
			root.scoreStateChanged({})
			root.inited = true
		}
		if (score == "uploaded") root.queueChanges({data: [{}], sendScore: true})
	} catch(e) {
		debugLog(e, 2)
	}
}
//handles realtime change
function handleChange(elementArrays, scoreString) {
	try {
		if (root.loadOlderFile) {
			root.loadOlderFile = false
			return
		}
		if (root.currentProjectOpen) {
			if (scoreString.length > 0) {
				root.busy = true
				handleSync(scoreString)
				root.busy = false
			}
			if (Array.isArray(elementArrays)) {
				if (elementArrays.length < 1) return
				for (var j in elementArrays) {
					var elements = elementArrays[j]
					if (Array.isArray(elements)) {
						if (elements.length < 1) continue
						if (elements[0].sender == root.userId) {
							debugLog("Aborting change (already present)", 1)
							continue
						}
						root.busy = true
						curScore.startCmd()
						for (var i in elements) {
							var el = elements[i]
							debugLog(("Received " + el.type + ": Tick " + el.startTick
								+ ", voice " + (el.track % 4 + 1) + ", staff " + Math.ceil((el.track + 1) / 4)), 1)
							switch (el.type) {
								case "note":
								case "rest":
								case "tuplet": {
									var c = curScore.newCursor()
									c.rewindToTick(el.startTick)
									c.track = el.track
									if (el.startTick != c.measure.firstSegment.tick) c.rewindToTick(el.startTick)
									if (c.element && c.element.tuplet) removeElement(getMotherTuplet(c.element))
									if (el.type == "tuplet") addTupletObj(el)
									else addChordRestObj(el)
									break
								}
								case "spanner": {
									addSpanner(el)
									break
								}
								case "measures": {
									addMeasures(el)
									break
								}
							}
						}
						curScore.endCmd()
						root.busy = false
					}
				}
			}
		} else {
			root.missingLatestChanges = true
		}
	}
	catch(e) {
		debugLog(e, 2)
	}
}
function scoreLengthChanged() {
	var test = getScoreLength()
	if (test != root.prevState.scoreLength) {
		root.prevState.scoreLength = test
		return true
	}
	return false
}
function getScoreLength() {
	var len = (curScore.lastMeasure.firstSegment.tick + (4 * division * curScore.lastMeasure.timesigActual.numerator / curScore.lastMeasure.timesigActual.denominator))
	debugLog(("Score Length:" + len.toString()), 0)
	return len
}
//the paramaters determining when to send new changes, outside of a selection change
function scoreChanged() {
	return (tiesChanged() || visibleChanged() || placementChanged() || beamModeChanged() || offsetYChanged() || durationChanged())
}
function tiesChanged() {
	if (curScore.selection.elements.length && curScore.selection.elements[0].type == Element.NOTE) {
		var note = curScore.selection.elements[0]
		var test = !(isTie(note.tieForward) == root.prevState.ties.forward && isTie(note.tieBack) == root.prevState.ties.back)
		root.prevState.ties.forward = isTie(curScore.selection.elements[0].tieForward)
		root.prevState.ties.back = isTie(curScore.selection.elements[0].tieBack)
		return test
	}
	return false
}
function isTie(tie) {
	return (tie) ? true : false
}
function visibleChanged() {
	if (curScore.selection.elements.length) {
		if (curScore.selection.elements[0].visible == !root.prevState.visible) {
			root.prevState.visible = !root.prevState.visible
			return true
		}
	}
	return false
}
function placementChanged() {
	if (curScore.selection.elements.length) {
		var element = curScore.selection.elements[0]
		if (element.type == Element.DYNAMIC || element.type == Element.TEMPO_TEXT || element.type == Element.STAFF_TEXT
			|| element.type == Element.SYSTEM_TEXT || element.type == Element.FERMATA) {
			if (element.placement != root.prevState.placement) {
				root.prevState.placement = element.placement
				return true
			}
		}
	}
	return false
}
function beamModeChanged() {
	if (curScore.selection.elements.length) {
		var element = curScore.selection.elements[0]
		if (element.type == Element.NOTE || element.type == Element.REST) {
			if (getChordRest(element).beamMode != root.prevState.beamMode) {
				root.prevState.beamMode = getChordRest(element).beamMode
				return true
			}
		}
	}
	return false
}
function offsetYChanged() {
	if (curScore.selection.elements.length) {
		var element = curScore.selection.elements[0]
		if (element.type == Element.REST) {
			if (element.offsetY != root.prevState.offsetY) {
				root.prevState.offsetY = element.offsetY
				return true
			}
		}
	}
	return false
}
function updateStaffList() {
	staffList = []
	var c = curScore.newCursor()
	c.rewind(Cursor.SCORE_START)
	for (var i = 0; i < curScore.nstaves; i++) {
		c.staffIdx = i
		staffList.push(c.element.staff)
	}
}
function getStaff(element) {
	for (var i in staffList) {
		if (staffList[i].is(element.staff)) return Number(i) + 1
	}
	return false
}
function durationChanged() {
	if (curScore.selection.elements.length && curScore.selection.elements[0].type == Element.NOTE && curScore.selection.elements[0].noteType != NoteType.NORMAL) {
		var notedur = curScore.selection.elements[0].duration
		var tick = getTick(curScore.selection.elements[0])
		var track = curScore.selection.elements[0].track
		var test = root.prevState.tick == tick
		           && (notedur.numerator != root.prevState.duration.numerator
		               || notedur.denominator != root.prevState.duration.denominator)
		if (test) {
			root.prevState.duration.numerator = notedur.numerator
			root.prevState.duration.denominator = notedur.denominator
			root.prevState.duration.tick = tick
			root.prevState.duration.track = track
		}
		return test
	}
	return false
}
//creates a sendObj from a note/chord/rest
function getChordRestObj(element) {
	return {
		duration: getDuration(element),
		notes: getNotes(element),
		startTick: getTick(element),
		track: element.track,
		type: getType(element),
		annotations: getAnnotations(element),
		articulations: getArticulations(element),
		graceNotes: getGraceNotes(element),
		ties: getTies(element),
		beamMode: getBeamMode(element),
		offsetY: element.type == Element.REST ? element.offsetY : false,
		visible: element.type == Element.REST ? element.visible : false
	}
}
//returns readable duration values from a note/chord/rest/tuplet
function getDuration(element) {
	return {numerator: getChordRest(element).duration.numerator, denominator: getChordRest(element).duration.denominator}
}
//returns the notes in a note/chord/rest
function getNotesArray(element) {
	switch (element.type) {
		case Element.REST: return [] //null
		default: return getChordRest(element).notes
	}
}
//creates readable information from the notes in a note/chord/rest
function getNotes(element) {
	var notes = []
	var chordNotes = getNotesArray(element)
	for (var i in chordNotes) {
		notes[i] = {
			pitch: chordNotes[i].pitch,
			tpc: chordNotes[i].tpc,
			tpc1: chordNotes[i].tpc1,
			tpc2: chordNotes[i].tpc2
		}
	}
	return notes
}
//allows identical treatment/parenthood of notes/chords/rests
function getChordRest(element) {
	switch (element.type) {
		case Element.NOTE: return element.parent
		default: return element
	}
}
//returns the segment of a given note/chord/rest
function getSegment(element) {
	return getChordRest(element).parent
}
//returns the tick of a given note/chord/rest/tuplet
function getTick(element) {
	return element.type == Element.TUPLET ? getTick(element.elements[0]) : getSegment(element).tick
}
//retrieves the annotations of a chordrest in a readable form
function getAnnotations(element) {
	var annotations = getSegment(element).annotations
	var annoList = []
	for (var i in annotations) {
		var el = annotations[i]
		var obj = {}
		switch (el.type) {
			case Element.TEMPO_TEXT: {
				debugLog("logging tempo marking", 1)
				obj = {
					text: el.text,
					tempo: el.tempo,
					tempoFollowText: el.tempoFollowText
				}
				break
			}
			case Element.STAFF_TEXT:
			case Element.SYSTEM_TEXT: {
				debugLog("logging staff/system text", 1)
				obj = {
					text: el.text,
					fontStyle: el.fontStyle
				}
				break
			}
			case Element.DYNAMIC: {
				debugLog("logging dynamic", 1)
				obj = {
					text: el.text,
					velocity: el.velocity,
					dynamicRange: el.dynamicRange,
					veloChange: el.veloChange
				}
				break
			}
			case Element.FERMATA: {
				debugLog("logging fermata", 1)
				obj = {
					symbol: el.symbol,
					timeStretch: el.timeStretch
				}
				break
			}
			default: {
				debugLog("Unknown annotation element", 2)
				logMessage("Unknown annotation element")
				break
			}
		}
		obj.type = el.type
		obj.visible = el.visible
		obj.placement = el.placement
		annoList.push(obj)
	}
	return annoList
}
//retrieves the chordrest an annotation is connected to
function getChordRestFromAnnotation(annotation) {
	var annoCursor = curScore.newCursor()
	annoCursor.track = annotation.track
	annoCursor.rewindToTick(getSegment(annotation).tick)
	return annoCursor.element
}
//retrieves a chordrests articulations
function getArticulations(element) {
	var artiList = []
	if (element.type == Element.REST) return artiList
	var busytracker = root.busy
	root.busy = true
	var storedSelection = false
	if (!curScore.selection.isRange) {
		storeSelection()
		storedSelection = true
		//curScore.selection.selectRange(getTick(element), getTick(element) + 481, getStaff(element) - 1, getStaff(element))
		cmd("select-all")
	}
	for (var i in curScore.selection.elements) {
		if (curScore.selection.elements[i].type == Element.ARTICULATION && getTick(curScore.selection.elements[i].parent) == getTick(element)
			&& curScore.selection.elements[i].track == element.track) {
			artiList.push({
				placement: curScore.selection.elements[i].placement,
				play: curScore.selection.elements[i].play,
				symbol: curScore.selection.elements[i].symbol,
				visible: curScore.selection.elements[i].visible
			})
		}
	}
	if (storedSelection) retrieveSelection()
	root.busy = busytracker
	return artiList
}
//retrieves a chordrests grace notes
function getGraceNotes(element) {
	if (element.type == Element.REST) return []
	if (getChordRest(element).graceNotes) {
		var graceList = []
		var graceNotes = getChordRest(element).graceNotes
		for (var i in graceNotes) {
			var graceChord = graceNotes[i]
			graceList.push({
				duration: getDuration(graceChord),
				notes: getNotes(graceChord),
				type: getGraceNoteType(graceChord)
			})
		}
		return graceList
	}
	return []
}
//retrieves the type of grace note, formatted for sendObj
//doesnt work with switch for some reason
function getGraceNoteType(graceChord) {
	var type = graceChord.notes[0].noteType
	if (type == NoteType.ACCIACCATURA)	return "acciaccatura"
	if (type == NoteType.APPOGGIATURA)	return "appoggiatura"
	if (type == NoteType.GRACE4)		return "grace4"
	if (type == NoteType.GRACE16)		return "grace16"
	if (type == NoteType.GRACE32)		return "grace32"
	if (type == NoteType.GRACE8_AFTER)	return "grace8after"
	if (type == NoteType.GRACE16_AFTER)	return "grace16after"
	if (type == NoteType.GRACE32_AFTER)	return "grace32after"
	return "invalid"
}
//retrieves the chordrest a grace note is connected
function getChordRestFromGraceNote(graceNote) {
	return getChordRest(graceNote).parent
}
//retrieves a list of notes with ties in a chordrest
function getTies(element) {
	if (element.type == Element.REST) return []
	var tieList = []
	for (var i in getChordRest(element).notes) {
		if (getChordRest(element).notes[i].tieForward) {
			tieList.push({
				startTick: getTick(element),
				track: element.track,
				note: i
			})
		}
		if (getChordRest(element).notes[i].tieBack) {
			tieList.push({
				startTick: getTick(getChordRest(element).notes[i].tieBack.startNote),
				track: getChordRest(element).notes[i].tieBack.startNote.track,
				note: i
			})
		}
	}
	return tieList
}
function getBeamMode(element) {
	return getChordRest(element).beamMode
}
//returns the mother tuplet (unnested tuplet)
function getMotherTuplet(element) {
	var tuplet = element
	while (tuplet.tuplet) {
		tuplet = tuplet.tuplet
	}
	return tuplet
}
//creates a sendObj from a tuplet
function getTupletObj(tuplet) {
	return {
		duration: getDuration(tuplet),
		type: getType(tuplet),
		startTick: getTick(tuplet),
		track: tuplet.track,
		elements: getTupletElements(tuplet),
		ratio: getTupletRatio(tuplet),
		bracketType: tuplet.bracketType,
		numberType: tuplet.numberType,
		visible: tuplet.visible
	}
}
//returns the ratio of a given tuplet
function getTupletRatio(tuplet) {
	return {numerator: tuplet.actualNotes, denominator: tuplet.normalNotes}
}
//returns the chordrests within a tuplet
function getTupletElements(tuplet) {
	var elementsArray = []
	for (var i in tuplet.elements) {
		if (getType(tuplet.elements[i]) == "tuplet") {
			elementsArray.push(getTupletObj(tuplet.elements[i]))
		} else {
			elementsArray.push(getChordRestObj(tuplet.elements[i]))
		}
	}
	return elementsArray
}
//returns a readable 'type' property for elements
function getType(element) {
	switch (element.type) {
		case Element.NOTE:
		case Element.CHORD:   return "note"
		case Element.REST:    return "rest"
		case Element.TUPLET:  return "tuplet"
		case Element.TIMESIG: return "timesig"
		default:              return "unknown"
	}
}
//returns readable data for adding spanners
function getSpanner(spanner) {
	if (!curScore.selection.elements.length) return
	var sendObj = {
		type: "spanner",
		subtype: spanner,
		sender: root.userId,
		selection: getTickableSelection()
	}
	if (!sendObj.selection) return debugLog(("Unable to add " + spanner + ", invalid selection"), 2)
	root.queueChanges({data: [sendObj], sendScore: false})
	var busytracker = root.busy
	root.busy = true
	cmd("add-" + spanner)
	cmd("escape")
	root.busy = busytracker
}
//returns readable data for adding measures
function getMeasures(addType, count) {
	var sendObj = {
		type: "measures",
		subtype: addType,
		count: count,
		sender: root.userId,
		selection: true
	}
	if (addType == "insert") sendObj.selection = getTickableSelection()
	if (!sendObj.selection) return debugLog("Unable to add measures, invalid selection", 2)
	root.queueChanges({data: [sendObj], sendScore: false})
	var busytracker = root.busy
	root.busy = true
	if (addType == "append") curScore.appendMeasures(count)
	else for (var i = 0; i < count; i++) {cmd("insert-measure")}
	root.prevState.scoreLength = getScoreLength()
	root.scoreStateChanged({})
	root.busy = busytracker
	delete sendObj
}
function getTickableSelection() {
	var selection = {
		isRange: curScore.selection.isRange
	}
	if (selection.isRange) {
		selection.startSegment = curScore.selection.startSegment.tick
		selection.endSegment   = curScore.selection.endSegment.tick
		selection.startStaff   = curScore.selection.startStaff
		selection.endStaff     = curScore.selection.endStaff
	} else {
		selection.elements = []
		for (var i in curScore.selection.elements) {
			var element = curScore.selection.elements[i]
			if (getType(element) == "note" || getType(element) == "rest") {
				selection.elements.push({
					startTick: getTick(element),
					track: element.track
				})
			}
		}
		if (selection.elements.length < 1) return false
	}
	return selection
}
//adds chordrests to the score
function addChordRestObj(element) {
	var c = curScore.newCursor()
	c.rewindToTick(element.startTick)
	c.track = element.track
	if (element.startTick != c.measure.firstSegment.tick) c.rewindToTick(element.startTick)
	if (c.element) {
		c.setDuration(c.element.duration.numerator, c.element.duration.denominator)
		c.addRest()
		c.rewindToTick(element.startTick)
	}
	c.setDuration(element.duration.numerator, element.duration.denominator)
	if (element.type == "rest") {
		c.addRest()
		c.rewindToTick(element.startTick)
		//check for full measure rest
		if (c.element.duration.numerator / c.element.duration.denominator == c.measure.timesigActual.numerator / c.measure.timesigActual.denominator) {
			storeSelection()
			curScore.selection.select(c.element, false)
			cmd("full-measure-rest")
			retrieveSelection()
		}
		c.element.offsetY = element.offsetY
		c.element.visible = element.visible
	} else {
		for (var i in element.notes) {c.addNote(element.notes[i].pitch, i != 0)}
		c.rewindToTick(element.startTick)
		c.track = element.track
		for (var i in c.element.notes) {
			c.element.notes[i].tpc  = element.notes[i].tpc
			c.element.notes[i].tpc1 = element.notes[i].tpc1
			c.element.notes[i].tpc2 = element.notes[i].tpc2
		}
		addArticulations(c, element.articulations)
		addGraceNotes(c.element.notes[0], element.graceNotes)
		addTies(element.ties)
	}
	c.element.beamMode = element.beamMode
	addAnnotations(c, element.annotations)
	delete c
}
//adds tuplets and their contents to the score
function addTupletObj(element) {
	var c = curScore.newCursor()
	c.rewindToTick(element.startTick)
	c.track = element.track
	if (element.startTick != c.measure.firstSegment.tick) c.rewindToTick(element.startTick)
	try {
		c.addTuplet(fraction(element.ratio.numerator, element.ratio.denominator), fraction(element.duration.numerator, element.duration.denominator))
		c.rewindToTick(element.startTick)
		c.track = element.track
		c.element.tuplet.bracketType = element.bracketType
		c.element.tuplet.numberType = element.numberType
		c.element.tuplet.visible = element.visible
		for (var i in element.elements) {
			if (element.elements[i].type == "tuplet") addTupletObj(element.elements[i])
			else addChordRestObj(element.elements[i])
		}
	} catch (e) {debugLog(e, 2)}
	delete c
}
//adds annotations (dynamics, tempo text, etc) to the score
function addAnnotations(cursor, annotations) {
	for (var i in getSegment(cursor.element).annotations) {
		removeElement(getSegment(cursor.element).annotations[i])
	}
	if (annotations.length < 1) return
	for (var i in annotations) {
		var el = annotations[i]
		var obj = newElement(el.type)
		obj.visible = el.visible
		obj.placement = el.placement
		switch (el.type) {
			case Element.TEMPO_TEXT: {
				debugLog("adding tempo marking", 1)
				obj.text = el.text
				break
			}
			case Element.STAFF_TEXT:
			case Element.SYSTEM_TEXT: {
				debugLog("adding staff/system text", 1)
				obj.text = el.text
				obj.fontStyle = el.fontStyle
				break
			}
			case Element.DYNAMIC: {
				debugLog("adding dynamic", 1)
				obj.text = el.text
				obj.velocity = el.velocity
				obj.dynamicRange = el.dynamicRange
				obj.veloChange = el.veloChange
				break
			}
			case Element.FERMATA: {
				debugLog("adding fermata", 1)
				obj.symbol = el.symbol
				obj.timeStretch = el.timeStretch
				break
			}
		}
		cursor.add(obj)
		if (el.type == Element.TEMPO_TEXT) {
			obj.tempo = el.tempo
			obj.tempoFollowText = el.tempoFollowText
			//crash if applying before adding
		}
		delete obj
	}
}
//adds articulations from sendObj
function addArticulations(cursor, artiList) {
	//if (artiList.length < 1) return
	for (var i in artiList) {
		var obj = newElement(Element.ARTICULATION)
		obj.placement = artiList[i].placement
		obj.play = artiList[i].play
		obj.symbol = artiList[i].symbol
		obj.visible = artiList[i].visible
		cursor.add(obj)
		delete obj
	}
}
//adds grace notes from sendObj
function addGraceNotes(note, graceList) {
	var graceNotes = note.parent.graceNotes
	if (graceList.length > 0) {
		storeSelection()
		for (var i in graceNotes) {
			removeElement(graceNotes[0])
		}
		for (var i = (graceList.length-1); i >= 0; i--) {
			curScore.selection.select(note, false)
			cmd(graceList[i].type)
		}
		for (var i in graceList) {
			curScore.selection.select(graceNotes[i].notes[0], false)
			applyGraceNoteDuration(graceNotes[i].notes[0], graceList[i].duration)
			
			for (var j in graceList[i].notes) {
				curScore.selection.select(graceNotes[i].notes[j], false)
				if (j != 0) {
					cmd("chord-e")
					cmd("note-input") //cancel chord-e effect
				}
				graceNotes[i].notes[j].pitch = graceList[i].notes[j].pitch
				graceNotes[i].notes[j].tpc = graceList[i].notes[j].tpc
				graceNotes[i].notes[j].tpc1 = graceList[i].notes[j].tpc1
				graceNotes[i].notes[j].tpc2 = graceList[i].notes[j].tpc2
			}
		}
		retrieveSelection()
	}
}
function applyGraceNoteDuration(note, targetDuration) {
	debugLog(qsTr("Calculating grace note duration..."), 1)
	var startN = note.parent.duration.numerator
	var startD = note.parent.duration.denominator
	var endN = targetDuration.numerator
	var endD = targetDuration.denominator
	
	debugLog(qsTr("Removing dots..."), 1)
	switch (note.dots.length) {
		case 4:
		case 3: {
			cmd("pad-dot" + note.dots.length)
			break
		}
		case 2: {
			cmd("pad-dotdot")
			break
		}
		case 1: {
			cmd("pad-dot")
			break
		}
		default: debugLog(qsTr("No dots detected"), 1)
	}
	debugLog(qsTr("Calculating base duration..."), 1)
	var i = -1
	while (Math.pow(2, i) < (endD / endN)) i++
	switch (Math.pow(2, i)) {
		case 0.25: {
			cmd("note-longa")
			break
		}
		case 0.5: {
			cmd("note-breve")
			break
		}
		default: cmd("pad-note-" + Math.pow(2, i))
	}
	debugLog(qsTr("Adding dots..."), 1)
	switch(endN) {
		case 31:
		case 15: {
			cmd("pad-dot" + note.dots.length)
			break
		}
		case 7: {
			cmd("pad-dotdot")
			break
		}
		case 3: {
			cmd("pad-dot")
			break
		}
		default: debugLog(qsTr("No dots added"), 1)
	}
}
//adds ties
function addTies(tieList) {
	storeSelection()
	for (var i in tieList) {
		var c = curScore.newCursor()
		c.rewindToTick(tieList[i].startTick)
		c.track = tieList[i].track
		if (tieList[i].startTick != c.measure.firstSegment.tick) c.rewindToTick(tieList[i].startTick)
		if (!c.element || c.element.type == Element.REST) return debugLog("Unable to add tie, notes missing", 2)
		curScore.selection.select(c.element.notes[tieList[i].note], false)
		cmd("tie")
		delete c
	}
	retrieveSelection()
}
//adds spanner
function addSpanner(spannerObj) {
	debugLog(("adding " + spannerObj.subtype), 1)
	var busytracker = root.busy
	root.busy = true
	storeSelection()
	loadTickableSelection(spannerObj.selection)
	cmd("add-" + spannerObj.subtype)
	cmd("escape")
	retrieveSelection()
	root.busy = busytracker
}
//adds measures
function addMeasures(measuresObj) {
	debugLog((measuresObj.subtype + "ing measures"), 1)
	var busytracker = root.busy
	root.busy = true
	if (measuresObj.subtype == "append") curScore.appendMeasures(measuresObj.count)
	else {
		storeSelection()
		loadTickableSelection(measuresObj.selection)
		for (var i = 0; i < measuresObj.count; i++) {cmd("insert-measure")}
		retrieveSelection()
	}
	root.prevState.scoreLength = getScoreLength()
	root.busy = busytracker
}
function loadTickableSelection(selection) {
	if (selection.isRange) {
		curScore.selection.selectRange(
			selection.startSegment,
			selection.endSegment,
			selection.startStaff,
			selection.endStaff
		)
	} else {
		for (var i in selection.elements) {
			var element = retrieveElement(selection.elements[i])
			curScore.selection.select(element, true)
		}
	}
}
function retrieveElement(element) {
	var c = curScore.newCursor()
	c.rewindToTick(element.startTick)
	c.track = element.track
	if (element.startTick != c.measure.firstSegment.tick) c.rewindToTick(element.startTick)
	if (c.element) return (c.element.type == Element.CHORD ? c.element.notes[0] : c.element)
}
function storeSelection() {
	root.selection = readSelection()
	curScore.selection.clear()
}
function retrieveSelection() {
	curScore.selection.clear()
	writeSelection(root.selection)
	root.selection = false
}
function readSelection() {
	var selectObj
	if (!curScore.selection.elements.length) return false
		if (curScore.selection.isRange) {
			selectObj = {
				isRange: true,
				startSegment: curScore.selection.startSegment.tick,
				endSegment: curScore.selection.endSegment.tick,
				startStaff: curScore.selection.startStaff,
				endStaff: curScore.selection.endStaff
			}
		} else {
			selectObj = {
				isRange: false,
				elements: []
			}
			for (var i in curScore.selection.elements) {
				selectObj.elements.push(curScore.selection.elements[i])
			}
		}
	return selectObj
}
function writeSelection(selectObj) {
	if (!selectObj) return
	if (selectObj.isRange) {
		curScore.selection.selectRange(
			selectObj.startSegment,
			selectObj.endSegment,
			selectObj.startStaff,
			selectObj.endStaff
		)
	} else {
		for (var i in selectObj.elements) {
			curScore.selection.select(selectObj.elements[i], true)
		}
	}
}
