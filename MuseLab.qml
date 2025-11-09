import MuseScore 3.0
import QtQuick 2.0
import QtQuick 2.3 as IMG
import QtQuick.Controls 2.2
import QtQuick.Window 2.3
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.2
import Qt.labs.settings 1.0
import FileIO 3.0
import "assets"
import "assets/utils.js" as Utils
import "tools/lz-string.js" as LZString
import "tools/MuseScoreIntegration.js" as MSI

MuseScore {
	menuPath: "Plugins.MuseLab"
	version: "0.9.3-beta"
	description: qsTr("Real-time MuseScore collaboration is here: MuseLab allows for synchronous score editing on multiple devices, anywhere in the world.")
	property bool dockable: false
	requiresScore: false
	implicitWidth: 640
	implicitHeight: 480
	id: root
	pluginType: dockable ? "dock" : ""
	dockArea: dockable ? "right" : ""
	
	//vars=======================================
	property bool	dev: false
	property string	host: "api.muselab.app"
	property string	apiPath: "/api"
	property string	nVersion: ""
	property string	token: ""
	property int	currentProjectId: 0
	property string	currentProjectName: ""
	property var	currentProjectObj: {projectId: 0; name: ""}
	property var	log: [{text: qsTr("Loading Score, please wait..."), initial: true}]
	property string	currentSession: ""
	property bool	canSave: true
	property bool 	inited: false
	property string code: ""
	property string	currentVersion: root.version //bypass annoying console error message
	property int	userId: -1
	property string	userName: ""
	property bool	currentProjectOpen: false
	property bool	missingLatestChanges: false
	property string	changelog: "<h3>v0.9.2</h3>\n<ul>
	<li>New UI</li>
	<li>Chat in project rooms</li>
	<li>Manage projects from within the plugin</li>
	<li>Grace note compatibility</li>
	<li>Ties compatibility</li>
	<li>Tuplets compatibility</li>
	<li>Dynamics, staff text, system text, fermatas, tempo text compatibility</li>
	<li>Multiple voices compatibility</li>
	</ul>"
	property int	logModeSeverity: 2 //3 most severe, 0 least, recommended: 2
	property string	errorLog: ""
	property var	selection: false
	property bool	busy: false
	property var	loadOlderFile: false
	property var	changeQueue: []
	property var	staffList: []
	property var	prevState: MSI.prevState
	//===========================================
	
	Component.onCompleted: {
		if (mscoreMajorVersion >= 4) root.title = "MuseLab"
	}
	onRun: {
		if (mscoreMajorVersion >= 4) {
			debugLog(qsTr("Unsupported MuseScore version."), 3)
			mu4Dialog.open()
		} else
		if ((mscoreMinorVersion < 6) || mscoreMajorVersion < 3) {
			debugLog(qsTr("Unsupported MuseScore version."), 3)
			mu321Dialog.open()
		} else {
			debugLog(("Running MuseLab v" +  root.version), 2)
			pluginWindow.visible = true
			if (!dev) getVersion()
		}
	}
	//temp File
	FileIO {
		id: tempXMLFile
		source: tempPath() + "/muselab_project.mscx"
		onError: debugLog(msg, 3)
	}
	//upload File
	FileIO {
		id: uploadXMLFile
		source: tempPath() + "/muselab_project.mscx"
		onError: debugLog(msg, 3)
	}
	//save File
	FileIO {
		id: saveXMLFile
		onError: debugLog(msg, 3)
	}
	//save File
	FileIO {
		id: hardSyncFile
		onError: debugLog(msg, 3)
	}
	function debugLog(message, severity) {
		errorLog += ("\r\n" + Date.now() + "--<" + message.toString() + ">")
		if (severity >= root.logModeSeverity) {
			console.log(message.toString())
			if (!root.log[0].initial) logMessage(message.toString())
		}
	}
	onScoreStateChanged: MSI.scoreStateChanged(state)
	
	//Takes response type from server
	property var messageTypes: ({
		NoChanges:0, Close:1, Login:2, Join: 3, Leave: 4, Sync:5, ChangeScore:6, Meta:7
	})
	//logs message on project screen
	function logMessage(message) {
		if (root.log[0].initial) {
			root.log = [{text: message.toString(), initial: false}]
		} else {
			var newModel = root.log
			newModel.push({text: message.toString(), initial: false})
			root.log = newModel
		}
	}
	//checks for plugin version on launch, and opens the necessary pages
	function getVersion() {
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = request.responseText
					nVersion = JSON.parse(response).version
					debugLog(("Latest available version: " + nVersion), 2)
					debugLog(("Current installed version: " + root.version), 2)
					if (nVersion == root.version) {
						debugLog("versions match!", 2)
						stackView.replace(stackView.initialItem, titlePage)
					} else {
						debugLog("versions dont match :(", 2)
						stackView.replace(stackView.initialItem, versionErrorPage, StackView.PushTransition)
					}
				} else {
					debugLog("Error checking plugin version", 2)
					connectionErrorDialog.open()
				}
			}
		}
		request.open("GET", getApiUrl("/plugin/version"), true)
		request.send()
	}
	//Joins a project using an invite code
	function getProjectDetailsAndJoin(inviteCode) {
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = JSON.parse(request.responseText)
					root.currentProjectId = response.project_id
					root.currentProjectName = response.project_name
					stackView.push(currentProjectPage)
					startSocket(inviteCode)
				} else {
					debugLog("Error joining Project", 2)
					projectPage.useCodeTextV = false
					projectPage.projectSelectButtonE = true
					projectPage.useCodeButtonE = true
					projectPage.useCodeFieldE = true
					projectPage.createProjectButtonE = true
					projectPage.projectPageErrorMessage = qsTr("Unable to join project.")
				}
			}
		}
		request.open("GET", getApiUrl("/polling/details/" + inviteCode), true)
		request.send()
	}
	//Creates an invite code, used for others to join your project
	function generateInviteCode() {
		if (root.currentSession == "") return
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = JSON.parse(request.responseText)
					root.code = response.code
				} else debugLog("Error generating invite code", 2)
			}
		}
		request.open("GET",  getApiUrl("/polling/invite?session=" + root.currentSession), true)
		request.send()
	}
	//creates a muselab account and signs into the plugin with it
	function signUp(username, email, password) {
		pluginWindow.startLoading()
		var content = {
			"username":username,
			"email":email,
			"password":password
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				pluginWindow.stopLoading()
				signUpPage.signUpTextV = false
				if (request.status === 200) {
					signUpPage.signUpPageErrorMessage = ""
					signUpPage.signedUp = true
					signUpTimer.start()
				} else {
					signUpPage.signUpButtonE = true
					signUpPage.signUpPageErrorMessage = qsTr("Email or Username already exists!")
				}
			}
		}
		request.open("POST", getApiUrl("/auth/register?auto_login=true"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.send(JSON.stringify(content))
	}
	//request a password reset, via email
	function forgotPassword(email) {
		pluginWindow.startLoading()
		var content = {
			"email":email
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				pluginWindow.stopLoading()
				forgotPasswordPage.forgotPasswordTextV = false
				if (request.status === 200) {
					forgotPasswordPage.forgotPasswordPageError = ""
					debugLog(("PW reset email sent"), 2)
					stackView.pop() //instead: display a message "please check your email", and pop after 5/10 seconds have passed
				} else {
					forgotPasswordPage.fpPageResetButtonE = true
					forgotPasswordPage.forgotPasswordPageError = "Email not found!"
				}
			}
		}
		request.open("POST", getApiUrl("/auth/forgot_password"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.send(JSON.stringify(content))
	}
	//logs user into the plugin
	function login(username, password) {
		pluginWindow.startLoading()
		var content = {
			"username":username,
			"password":password
		}
		if (root.token !== "") {
			pluginWindow.stopLoading()
			debugLog("Already logged in", 2)
			return
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				pluginWindow.stopLoading()
				if (request.status === 200) {
					var response = request.responseText
					var json = JSON.parse(response)
					loginPage.loginPageErrorMessage = ""
					root.token = json.accessToken
					root.userId = json.id
					root.userName = username
					debugLog(("Logged in as " + root.userName), 2)
					stackView.replace(loginPage, projectPage, StackView.PushTransition)
					getProjects()
				} else {
					loginPage.loginTextV = false
					loginPage.canLogIn = true
					loginPage.lPFPButtonE = true
					loginPage.loginPageErrorMessage = (request.status === 403) ?
						qsTr("You must verify your account before logging in. Please check your email.") : qsTr("Username or password is incorrect.")
				}
			}
		}
		request.open("POST", getApiUrl("/auth/login"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.send(JSON.stringify(content))
	}
	//loads a users projects, to select from the menu
	function getProjects() {
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				projectPage.projectListModel = []
				projectPage.projectListCI = -1
				if (request.status === 200) {
					projectPage.projectPageErrorMessage = ""
					var response = request.responseText
					var json = JSON.parse(response)
					var pList = []
					for (var i in json) {
						if (json[i].version == mscoreMajorVersion) pList.push(json[i])
					}
					projectPage.projectListModel = pList
					if (projectPage.projectListModel.length == 0) {
						projectPage.projectListModel = [{name: "No projects"}]
						projectPage.projectListCI = 0
					} else {
						projectPage.projectListCI = 0
						for (var i in pList) {
							if (pList[i].projectId == projectSelectSettings.projectId) projectPage.projectListCI = i
						}
						projectPage.projectListE = true
						projectPage.projectSelectButtonE = true
					}
				} else {
					projectPage.projectPageErrorMessage = "Invalid auth token."
					debugLog(("Unable to load projects"), 2)
				}
			}
		}
		request.open("GET", getApiUrl("/projects/list"), true)
		request.setRequestHeader("Authorization", "Bearer " + root.token)
		request.send()
	}
	//loads info on a specific project
	function getProject(projectId, func) {
		debugLog("(Re)loading project", 1)
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = request.responseText
					var json = JSON.parse(response)
					func(json)
					debugLog("(Re)loaded project!", 1)
				} else {
					debugLog(("Unable to (re)load project"), 2)
					return
				}
			}
		}
		request.open("GET", getApiUrl("/projects/get/" + projectId), true)
		request.setRequestHeader("Authorization", "Bearer " + root.token)
		request.send()
	}
	//creates a new project and opens it
	function createProject(name) {
		var content = {
			"name": name,
			"version": mscoreMajorVersion
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				projectPage.createProjectTextV = false
				if (request.status === 200) {
					projectPage.projectPageErrorMessage = ""
					var response = request.responseText
					var json = JSON.parse(response)
					root.currentProjectId = json.id
					root.currentProjectName = json.name //does this work????
					stackView.push(currentProjectPage)
					startSocket("")
				} else {
					projectPage.createProjectButtonE = true
					projectPage.projectPageErrorMessage = "Invalid auth token."
				}
			}
		}
		request.open("POST", getApiUrl("/projects/create"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.setRequestHeader("Authorization", "Bearer " + root.token)
		request.send(JSON.stringify(content))
	}
	//adds a user to the current project
	function addUser(name) {
		var content = {
			"username":name
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				addUser3Button.enabled = true
				if (request.status !== 200) addUserDialog.addUserPageErrorMessage = qsTr("User does not exist!")
			}
		}
		request.open("POST", getApiUrl("/projects/" + root.currentProjectId + "/add/user"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.setRequestHeader("Authorization", "Bearer " + root.token)
		request.send(JSON.stringify(content))
	}
	//sends a message in the project log
	function sendMessage(message) {
		if (root.currentSession == "") return
		var content = {
			"message": message
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status !== 200) logMessage("Failed to send message!")
			}
		}
		request.open("POST", getApiUrl("/polling/messaging/send?session=" + root.currentSession), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.send(JSON.stringify(content))
	}
	//not really a socket, but sends the initial login request for long-polling
	function startSocket(inviteToken) {
		poll({
			type: messageTypes.Login,
			data: {
				token: root.token,
				project_id: root.currentProjectId,
				invite_token: inviteToken
			}
		}, "")
	}
    function getRecentChanges() {
		if (root.currentSession == "") return
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = request.responseText
					var json = JSON.parse(response)
					MSI.handleChange(json.data, json.score)
				}
			}
		}
		request.open("GET", getApiUrl("/polling/changes?session=" + root.currentSession), true)
		request.send()
	}
	function getScoreString(func) {
		if (root.currentSession == "") return
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					var response = request.responseText
					var json = JSON.parse(response)
					var resp = LZString.LZString.decompressFromBase64(json.score)
					func(resp)
				} else func("")
			}
		}
		request.open("GET", getApiUrl("/polling/score?session=" + root.currentSession), true)
		request.send()
	}
	function getApiUrl(path) {
		return (dev ? "http" : "https") + "://" + host + apiPath + path
	}
	function queueChanges(changeObj) {
		if (!root.currentProjectOpen) return
		changeQueue.push(changeObj)
		if (!queueTimer.running) queueTimer.start()
	}
	Timer {
		id: queueTimer
		interval: 10 //ms
		repeat: true
		triggeredOnStart: true
		onTriggered: {
			if (changeQueue.length == 0) stop()
			else sendChanges(changeQueue.shift())
		}
	}
	//send changes to seperate endpoint
	function sendChanges(changeObj) {
		if (root.currentSession == "") return
		var sendObj = {}
		
		if (changeObj.sendScore) {
			var fileName = "muselab_save-" + Date.now()
			hardSyncFile.source = hardSyncFile.tempPath() + "/" + fileName + ".mscx"
			writeScore(curScore, hardSyncFile.source, "mscx")
			
			sendObj.type = messageTypes.Sync
			sendObj.score = LZString.LZString.compressToBase64(hardSyncFile.read())
			sendObj.data = {}
			root.scoreStateChanged({})
		} else {
			// Add the type field for CHANGESCORE messages
			sendObj.type = messageTypes.ChangeScore  // This adds type: 6
			sendObj.data = changeObj.data
			sendObj.score = ""
		}
		
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status !== 200) debugLog(qsTr("Error making changes to project"), 2)
				if (changeObj.sendScore) hardSyncFile.remove(hardSyncFile.source)
			}
		}
		request.open("POST", getApiUrl("/polling/update?session=" + root.currentSession), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.send(JSON.stringify(sendObj))
	}
	//send changes to seperate endpoint
	function saveScore(func) {
		if (root.currentSession == "") return
		if (root.currentProjectOpen) {
			root.canSave = false
			var fileName = "muselab_save-" + (Date.now())
			saveXMLFile.source = saveXMLFile.tempPath() + "/" + fileName + ".mscx"
			writeScore(curScore, saveXMLFile.source, "mscx")
			cmd("file-save")
			var xhr = new XMLHttpRequest()
			xhr.onreadystatechange = function() {
				if (xhr.readyState === XMLHttpRequest.DONE) {
					if (xhr.status === 200) {
						root.canSave = true
						if (func) func()
						else root.getProject(root.currentProjectId, function (json) {currentProjectPage.currentProjectObj = json})
					} else {
						logMessage("Failed to save score")
						root.canSave = true
					}
				}
			}
			var boundary = "---------------------------" + (new Date()).getTime().toString(16)
			var body = "--" + boundary + "\r\n"
			body += 'Content-Disposition: form-data; name="name"\r\n\r\n'
			body += fileName + ".mscx"
			body += "\r\n--" + boundary + "\r\n"
			body += 'Content-Disposition: form-data; name="project_id"\r\n\r\n'
			body += root.currentProjectId
			body += "\r\n--" + boundary + "\r\n"
			body += 'Content-Disposition: form-data; name="file"; filename="' + fileName + ".mscx" + '"\r\n'
			body += 'Content-Type: text/xml\r\n\r\n'
			body += saveXMLFile.read()
			body += "\r\n--" + boundary
			xhr.open("POST", getApiUrl("/files/upload"))
			xhr.setRequestHeader("Authorization", "Bearer " + root.token)
			xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary)
			xhr.send(body)
		}
	}
	//handles all incoming and outgoing data for polling
	function poll(data, session) {
		try {
			var xhr = new XMLHttpRequest()
			xhr.onreadystatechange = function() {
				if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
					var newSession = xhr.getResponseHeader("session")
					if (newSession !== "" && newSession !== session) {
						session = newSession
						root.currentSession = newSession
						pollForMessages(newSession)
					}
				} else if (xhr.readyState === XMLHttpRequest.DONE) {
					if (xhr.status === 200) {
						var response = JSON.parse(xhr.responseText)
						switch (response.type) {
							//NOCHANGES
							case messageTypes.NoChanges: {
								debugLog(("Poll: No changes"), 0)
								poll({type: messageTypes.NoChanges}, session)
								break
							}
							//JOIN
							case messageTypes.Join: {
								debugLog(("Poll: User joined project"), 1)
								root.updateCurrentUsers(response.users)
								if (root.userId == response.data.user) poll({type: messageTypes.Sync, data: {}}, session)
								else {
									logMessage(response.data.message)
									poll({type: messageTypes.NoChanges}, session)}
								break
							}
							//LEAVE
							case messageTypes.Leave: {
								debugLog(("Poll: User left project"), 1)
								root.updateCurrentUsers(response.users)
								logMessage(response.data.message)
								poll({type: messageTypes.NoChanges}, session)
								break
							}
							case messageTypes.Close: {
								debugLog(("Poll: Closing project session"), 1)
								logMessage("Connection closed by server")
								break
							}
							case messageTypes.Sync: {
								debugLog(("Poll: Resyncing Project"), 0)
								root.busy = true
								if (response.data.user != root.userId) MSI.handleSync(response.data.score)
								root.busy = false
								poll({type: messageTypes.ChangeScore}, session)
								break
							}
							case messageTypes.ChangeScore: {
                                debugLog(JSON.stringify(response.data), 0)
								debugLog(("Poll: Applying changes to project"), 0)
								MSI.handleChange(response.data, response.score)
								poll({type: messageTypes.NoChanges}, session)
								break
							}
							case messageTypes.Meta: {
								debugLog(("Poll: Updating project metadata"), 1)
								//xiao, do your witchcraft pleaseeeeeee
								//response.data is the project obj
								poll({type: messageTypes.NoChanges}, session)
								break
							}
							default: {
								debugLog(("Poll: Unknown response type: " + response.type), 1)
								logMessage("Poll: Unknown response type: " + response.type)
								break
							}
						}
					} else {
						debugLog(("HTTP error: " + xhr.status + " " + xhr.statusText), 2)
					}
				}
			}
			xhr.open("POST", session !== "" ? getApiUrl("/polling/message?session=" + session) : getApiUrl("/polling/message"))
			xhr.setRequestHeader("Content-Type", "application/json")
			xhr.send(JSON.stringify(data))
		}
		catch(e) {
			logMessage(e)
		}
	}
	function getFileNameFromPath(filePath) {
		if (filePath.includes('/')) return filePath.split('/').pop()
		if (filePath.includes('\\')) return filePath.split('\\').pop()
		return filePath
	}
	//--------------------------------------------------------------
	//Message Polling below, I know comments from me are unheard of
	//--------------------------------------------------------------
	function pollForMessages(session) {
		try {
			var xhr = new XMLHttpRequest()
			xhr.onreadystatechange = function() {
				if (xhr.readyState === XMLHttpRequest.DONE) {
					if (xhr.status === 200) {
						if (xhr.responseText.length > 0) {
							var response = JSON.parse(xhr.responseText)
							debugLog(xhr.responseText, 1)
							logMessage(response.message)
						}
						pollForMessages(session)
					} else debugLog(("HTTP error: " + xhr.status + " " + xhr.statusText), 2)
				}
			}
			xhr.open("GET", getApiUrl("/polling/messaging/subscribe?session="+session), true)
			xhr.send()
		}
		catch(e) {
			logMessage(e)
		}
	}
	function updateCurrentUsers(userList) {
		var newList = []
		for (var i in userList) {
			var test = true
			for (var j in newList) {
				if (newList[j].id == userList[i].id) {
					test = false
					break
				}
			}
			if (test) newList.push(userList[i])
		}
		cppUsersList.model = newList
	}
	function sendFeedback(projectId, errorLog) {
		var content = {
			"projectId": projectId,
			"log": LZString.LZString.compressToBase64(errorLog)
		}
		var request = new XMLHttpRequest()
		request.onreadystatechange = function() {
			if (request.readyState == XMLHttpRequest.DONE) {
				if (request.status === 200) {
					debugLog("Your feedback was sent!", 2)
					logMessage("Your feedback was sent!")
				}
			}
		}
		request.open("POST", getApiUrl("/logging/send"), true)
		request.setRequestHeader("Content-Type", "application/json")
		request.setRequestHeader("Authorization", "Bearer "+root.token)
		request.send(JSON.stringify(content))
	}
	function logOut() {
		for (var i in scores) {
			if (curScore.metaTag("project-id") == root.currentProjectId) {
				//cmd("file-save") //write score to the current path?
				//saveXMLFile.remove(saveXMLFile.source)
				var fileName = "muselab_save-" + (Date.now())
				saveXMLFile.source = saveXMLFile.tempPath() + "/" + fileName + ".mscx"
				
				writeScore(curScore, saveXMLFile.source, "mscx")
				pluginWindow.raise()
				getScoreString(function (score) {
					if (formatScoreFile(score) == formatScoreFile(saveXMLFile.read())) {
						debugLog(qsTr("Project is saved online. Closing score..."), 1)
						finishLogOut()
					} else {
						debugLog(qsTr("Project i"))
						savePromptDialog.open()
					}
				})
				return
			} else {
				if (i == 0) cmd("escape")
				cmd("next-score")
				if (+i + 1 == scores.length) {
					debugLog(qsTr("Project already closed, unable to check saves"), 1)
					finishLogOut()
				}
			}
		}
	}
	function finishLogOut() {
		if (curScore.metaTag("project-id") == root.currentProjectId) closeScore(curScore)
		debugLog(qsTr("Logging out..."), 2)
		poll({type:messageTypes.Close, data: {}}, root.currentSession)
		root.inited = false
		root.currentProjectId = 0
		root.currentProjectName = ""
		root.currentSession = ""
		root.log = [{text: qsTr("Loading Score, please wait..."), initial: true}]
		pluginWindow.raise()
	}
	function formatScoreFile(scoreString) {
		//remove different xml opening header
		var newScoreString = scoreString.replace(/^<\?.+?\?>\n?.*?</g, '<?xml version="1.0" encoding="UTF-8"?>\n<')
		//remove layertag difference
		newScoreString = newScoreString.replace(/^ *<LayerTag.*>$/gm, '<LayerTag id="0" tag="default"/>')
		//remove difference in formatting of empty metaTags
		newScoreString = newScoreString.replace(/^ *<metaTag name="[A-z]*?"><\/metaTag>$/gm, "")
		newScoreString = newScoreString.replace(/^ *<metaTag name="[A-z]*?"\/>$/gm, "")
		
		//remove reordering in instrument section objects
		var sectionArray = newScoreString.match(/^ *<section[^A-z].*>$/gm)
		for (var i in sectionArray) {
			var sectionString = "<section "
			sectionString += sectionArray[i].match(/barLineSpan="[a-z]+?"/g)[0]
			sectionString += " "
			sectionString += sectionArray[i].match(/brackets="[a-z]+?"/g)[0]
			sectionString += " "
			sectionString += sectionArray[i].match(/id="([a-z]|-)+?"/g)[0]
			sectionString += " "
			sectionString += sectionArray[i].match(/showSystemMarkings="[a-z]+?"/g)[0]
			sectionString += " "
			sectionString += sectionArray[i].match(/thinBrackets="[a-z]+?"/g)[0]
			sectionString += ">"
			newScoreString = newScoreString.replace(sectionArray[i], sectionString)
			delete sectionString
		}
		//remove reordering in instrument ordering tag
		var orderArray = newScoreString.match(/^ *<Order[^A-z].*>$/gm)
		for (var i in orderArray) {
			var orderString = "<Order "
			orderString += orderArray[i].match(/customized="[0-9]+?"/g)[0]
			orderString += " "
			orderString += orderArray[i].match(/id="[a-z]+?"/g)[0]
			orderString += ">"
			newScoreString = newScoreString.replace(orderArray[i], orderString)
			delete orderString
		}
		//remove reordering in instrument brackets
		var bracketArray = newScoreString.match(/^ *<bracket[^A-z].*>$/gm)
		for (var i in bracketArray) {
			var bracketString = "<bracket "
			bracketString += bracketArray[i].match(/col="[0-9]+?"/g)[0]
			bracketString += " "
			bracketString += bracketArray[i].match(/span="[0-9]+?"/g)[0]
			bracketString += " "
			bracketString += bracketArray[i].match(/type="[0-9]+?"/g)[0]
			bracketString += "/>"
			newScoreString = newScoreString.replace(bracketArray[i], bracketString)
			delete bracketString
		}
		newScoreString = newScoreString.replace(/<\/museScore>(\n| )*/g, "</museScore>")
		return newScoreString
	}

	ApplicationWindow {
		id:		 pluginWindow
		height:	 root.height
		width:	 root.width
		visible: false
		title:	 "MuseLab"
		//flags: Qt.WindowMinimizeButtonHint
		
		signal startLoading
		signal stopLoading
		
		onStartLoading: stackBusyTimer.start()
		
		onStopLoading: {
			stackBusyTimer.stop()
			stackBusyIndicator.visible = false
			stackView.opacity = 1.0
		}
		property var oldWidth
		Component.onCompleted: oldWidth = width
		onWidthChanged: {
			if (stackView.currentItem == currentProjectPage) cppMouseArea.widthX = Math.round(cppMouseArea.widthX * (width / oldWidth))
			oldWidth = width
		}
		Timer {
			id: stackBusyTimer
			interval: 5000
			onTriggered: {
				stackView.opacity = 0.7
				stackBusyIndicator.visible = true
			}
		}
		StyledBusyIndicator {
			id: stackBusyIndicator
			visible: false
			anchors.centerIn: parent
		}
		StackView {
			id: stackView
			anchors.fill: parent
			initialItem: dev ? hostPage : loadingPage
			onCurrentItemChanged: currentItem.reload()
			
			background: IMG.Image {
				source: "assets/muselab/background.svg"
				anchors.fill: parent
				fillMode: Image.PreserveAspectCrop // ensure it fits, no stretching
				mipmap: true // smoothing, available from QtQuick 2.3
				anchors.centerIn: parent
				
				IMG.Image {
					source: "assets/muselab/background.png"
					anchors.fill: parent
					fillMode: Image.PreserveAspectCrop // ensure it fits, no stretching
					mipmap: true // smoothing, available from QtQuick 2.3
					anchors.centerIn: parent
				}//Image
			}
			
			property int transitionDuration: 1000
			
			popEnter: Transition {IMG.XAnimator {from: (stackView.mirrored ? -1 : 1) * -stackView.width; to: 0; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			popExit: Transition {IMG.XAnimator {from: 0; to: (stackView.mirrored ? -1 : 1) * stackView.width; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			pushEnter: Transition {IMG.XAnimator {from: (stackView.mirrored ? -1 : 1) * stackView.width; to: 0; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			pushExit: Transition {IMG.XAnimator {from: 0; to: (stackView.mirrored ? -1 : 1) * -stackView.width; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			replaceEnter: Transition {IMG.YAnimator {from: (stackView.mirrored ? 1 : -1) * stackView.width; to: 0; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			replaceExit: Transition {IMG.YAnimator {from: 0; to: (stackView.mirrored ? 1 : -1) * -stackView.width; duration: stackView.transitionDuration; easing.type: Easing.OutCubic}}
			
			StackPage {
				id: hostPage
					
				Column {
					anchors.horizontalCenter: parent.horizontalCenter
					spacing: sizes.maxSpacing
					y: sizes.maxSpacing
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: "Host address:"
					}
					StyledTextField {
						anchors.horizontalCenter: parent.horizontalCenter
						id: hostField
						placeholderText: "Host..."
						text: host
						Keys.onReturnPressed: if (hostButton.enabled) hostButton.clicked()
					}
					StyledButton {
						id: hostButton
						anchors.horizontalCenter: parent.horizontalCenter
						text: "Next"
						enabled: (hostField.length != 0)
						
						onClicked: {
							host = hostField.text
							getVersion()
						}
					}
				}
			}
			StackPage {
				id: loadingPage
					
				Column {
					anchors.horizontalCenter: parent.horizontalCenter
					visible: !stackView.busy
					spacing: (1/20) * parent.height
					y: (3/20) * parent.height
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: "Loading MuseLab..."
						font.italic: true
					}
					StyledBusyIndicator {anchors.horizontalCenter: parent.horizontalCenter}
				}
			}
			StackPage {
				id: versionErrorPage
					
				Column {
					anchors.horizontalCenter: parent.horizontalCenter
					spacing: (1/20) * parent.height
					y: (3/20) * parent.height
					width: parent.width
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Update available! MuseLab v" + nVersion)
						font.pointSize: fontSizes.title
						width: Math.min((3/4) * parent.width, implicitWidth)
						wrapMode: Text.WordWrap
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						font.bold: false
						text: qsTr("A new version of MuseLab is available! Please update to the latest version to continue using MuseLab.")
						width: Math.min((3/4) * parent.width, implicitWidth)
						wrapMode: Text.WordWrap
					}
					GridLayout {
						columns: 2
						columnSpacing: sizes.maxSpacing
						rowSpacing: sizes.maxSpacing
						anchors.horizontalCenter: parent.horizontalCenter
						
						StyledLabel {text: qsTr("Current installed version:")}
						
						StyledTile {
							Layout.fillWidth: true
							Layout.minimumWidth: Math.max(children[1].width + 2 * children[1].anchors.rightMargin, sizes.buttonWidth)
							height: sizes.controlHeight
							
							StyledLabel {
								font.bold: false
								anchors {
									verticalCenter: parent.verticalCenter
									left: parent.left
									leftMargin: sizes.minSpacing
								}
								text: root.currentVersion
							}
						}
						
						StyledLabel {text: qsTr("Latest available version:")}
						
						StyledTile {
							Layout.fillWidth: true
							Layout.minimumWidth: Math.max(children[1].width + 2 * children[1].anchors.leftMargin, sizes.buttonWidth)
							height: sizes.controlHeight
							
							StyledLabel {
								font.bold: false
								anchors {
									verticalCenter: parent.verticalCenter
									left: parent.left
									leftMargin: sizes.minSpacing
								}
								text: root.nVersion
							}
						}
					}
					StyledButton {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Download")
						onClicked: {
							Qt.openUrlExternally("https://muselab.app/download")
							smartQuit()
						}
					}
				}
			}
			StackPage {
				id: titlePage
					
				onReload: {
					root.token = ""
					root.userId = -1
				}
				Column {
					spacing: (1/20) * parent.height
					anchors {
						fill: parent
						topMargin: titlePage.topSpace
					}
					Item {
						anchors.horizontalCenter: parent.horizontalCenter
						width: (3/4) * parent.width
						height: (2/5) * parent.height
						IMG.Image {
							source: "assets/muselab/banner.png"
							anchors.fill: parent
							fillMode: Image.PreserveAspectFit // ensure it fits, no stretching
							mipmap: true // smoothing, available from QtQuick 2.3
							anchors.centerIn: parent
						}
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Music collaboration made easy.")
						font.pointSize: fontSizes.subtitle
					}
					ColumnLayout {
						anchors.horizontalCenter: parent.horizontalCenter
						spacing: sizes.regSpacing
						StyledButton {
							implicitWidth: titlePage.optionWidth
							implicitHeight: 40
							accentButton: false
							text: qsTr("Log in")
							onClicked: stackView.push(loginPage)
						}

						StyledButton {
							implicitWidth: titlePage.optionWidth
							implicitHeight: 40
							text: qsTr("Sign Up")
							onClicked: stackView.push(signUpPage)
						}
					}//RowLayout
				}
				RowLayout {
					spacing: sizes.minSpacing
					anchors {
						left: parent.left
						bottom: parent.bottom
						leftMargin: loginPage.leftSpace
						bottomMargin: loginPage.bottomSpace
					}
					
					SmallLabel {text: "v" + currentVersion}
					
					SmallLabel {text: "|"}
					
					SmallButton {
						text: qsTr("What's new")
						onClicked: stackView.push(whatsNewPage)
					}
				}
				SmallButton {
					anchors {
						horizontalCenter: parent.horizontalCenter
						bottom: parent.bottom
						bottomMargin: loginPage.bottomSpace
					}
					text: qsTr("Web Portal")
					onClicked: Qt.openUrlExternally("https://muselab.app")
				}
				RowLayout {
					spacing: sizes.minSpacing
					anchors {
						right: parent.right
						bottom: parent.bottom
						rightMargin: loginPage.rightSpace
						bottomMargin: loginPage.bottomSpace
					}
					
					SmallButton {
						text: qsTr("About")
						onClicked: stackView.push(aboutPage)
					}
					
					SmallLabel {text: "|"}
					
					SmallButton {
						text: qsTr("Credits")
						onClicked: stackView.push(creditsPage)
					}
					
					SmallLabel {text: "|"}
					
					SmallButton {
						text: qsTr("Donate")
						onClicked: Qt.openUrlExternally("https://www.gofundme.com/f/muselab-a-collaboration-plugin-for-musescore")
					}
				}
			}
			StackPage {
				id: loginPage
					
				onReload: {
					loginTextV = false
					canLogIn = true
					lPFPButtonE = true
					loginPageErrorMessage = ""
					if (rememberUsername.checked) usernameField.text = lPsettings.unstore
					else usernameField.text = ""
					if (rememberPassword.checked) passwordField.text = lPsettings.pwstore
					else passwordField.text = ""
				}
				property bool	loginTextV: false
				property bool	canLogIn: true
				property bool	lPFPButtonE: true
				property string	loginPageErrorMessage: ""
				
				Column {
					spacing: (1/20) * parent.height
					anchors.centerIn: parent
					width: parent.width
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Log in to MuseLab")
						font.pointSize: fontSizes.heading
					}
					
					GridLayout {
						id: loginPageLayout
						rowSpacing: sizes.maxSpacing
						columnSpacing: sizes.regSpacing
						columns: 2
						anchors.horizontalCenter: parent.horizontalCenter
						
						StyledLabel {text: qsTr("Username:")}
						
						StyledTextField {
							id: usernameField
							implicitWidth: loginPage.optionWidth
							placeholderText: qsTr("Enter username")
							Keys.onReturnPressed: passwordField.forceActiveFocus()
						}

						StyledLabel {text: qsTr("Password:")}
						
						StyledTextField {
							id: passwordField
							implicitWidth: loginPage.optionWidth
							placeholderText: qsTr("Enter password")
							echoMode: TextInput.Password
							Keys.onReturnPressed: loginPageLoginButton.clicked()
						}
					}//GridLayout
					
					ColumnLayout {
						spacing: (1/100) * loginPage.height
						anchors {
							margins: sizes.regSpacing
							horizontalCenter: parent.horizontalCenter
						}
						enabled: loginPage.canLogIn
						opacity: (stackView.busy) ? 1.0 : (enabled ? 1.0 : colors.disabledOpacity)
						
						StyledCheckBox {
							id: rememberUsername
							text: qsTr("Remember Username")
						}
						
						StyledCheckBox {
							id: rememberPassword
							text: qsTr("Remember Password")
						}
					}//ColumnLayout
					
					RowLayout {
						anchors.horizontalCenter: parent.horizontalCenter
						spacing: sizes.regSpacing
						
						StyledButton {
							enabled: loginPage.lPFPButtonE
							opacity: (stackView.busy) ? 1.0 : (enabled ? 1.0 : colors.disabledOpacity)
							text: qsTr("Forgot Password")
							accentButton: false
							onClicked: {
								usernameField.text = ""
								passwordField.text = ""
								loginPage.loginPageErrorMessage = ""
								stackView.push(forgotPasswordPage)
							}
						}
						StyledButton {
							id: loginPageLoginButton
							enabled: loginPage.canLogIn
							opacity: (stackView.busy) ? 1.0 : (enabled ? 1.0 : colors.disabledOpacity)
							text: "Login"
							onClicked: {
								if (usernameField.text.length < 3 || passwordField.text.length < 6) loginPage.loginPageErrorMessage = qsTr("Username and password cannot be empty.")
								else {
									if (rememberUsername.checked) lPsettings.unstore = usernameField.text
									else lPsettings.unstore = ""
									if (rememberPassword.checked) lPsettings.pwstore = passwordField.text
									else lPsettings.pwstore = ""
									loginPage.canLogIn = false
									loginPage.lPFPButtonE = false
									loginPage.loginTextV = true
									loginPage.loginPageErrorMessage = ""
									login(usernameField.text, passwordField.text)
								}
							}
						}//Button
					}
				}
				Column {
					anchors {
						horizontalCenter: parent.horizontalCenter
						top: loginPageLayout.parent.bottom
						margins: sizes.regSpacing
					}
					spacing: sizes.regSpacing
					width: parent.width
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						visible: text != ""
						color: colors.red
						text: loginPage.loginPageErrorMessage
					}
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						visible: loginPage.loginTextV
						font.italic: true
						text: qsTr("Logging in...")
					}
				}
				Settings {
					id: lPsettings
					category: "MuseLab Plugin"
					property var unstore
					property var pwstore
					property alias rememberUsername: rememberUsername.checked
					property alias rememberPassword: rememberPassword.checked
				}
				BackButton {}
			}
			StackPage {
				id: forgotPasswordPage
				topSpace: (3/20) * height
					
				onReload: {
					forgotPasswordTextV = false
					fpPageResetButtonE = true
					forgotPasswordPageError = ""
				}
				property bool	forgotPasswordTextV: false
				property bool 	fpPageResetButtonE: true
				property string	forgotPasswordPageError: ""
				
				ColumnLayout {
					id: fpColumn
					spacing: (1/20) * parent.height
					y: forgotPasswordPage.topSpace
					anchors.centerIn: parent
					width: parent.width
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Password Reset")
						font.pointSize: fontSizes.heading
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						font.bold: false
						text: qsTr("A link to reset your account's password will be sent via email.")
						Layout.maximumWidth: (3/4) * parent.width
						wrapMode: Text.WordWrap
					}
					StyledTextField {
						anchors.horizontalCenter: parent.horizontalCenter
						id: emailField
						implicitWidth: forgotPasswordPage.optionWidth
						placeholderText: "Enter email address..."
						Keys.onReturnPressed: fpPageResetButton.clicked()
					}
					StyledButton {
						id: fpPageResetButton
						anchors.horizontalCenter: parent.horizontalCenter
						text: "Reset Password"
						enabled: forgotPasswordPage.fpPageResetButtonE
						
						onClicked: {
							if (!(/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/g.test(emailField.text))) forgotPasswordPage.forgotPasswordPageError = "Please enter a valid email."
							else {
								forgotPasswordPage.forgotPasswordPageError = ""
								forgotPasswordPage.fpPageResetButtonE = false
								forgotPasswordPage.forgotPasswordTextV = true
								forgotPassword(emailField.text)
							}
						}
					}
				}				
				ColumnLayout {
					anchors {
						horizontalCenter: parent.horizontalCenter
						top: fpColumn.bottom
						margins: sizes.regSpacing
					}
					spacing: sizes.regSpacing
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						visible: text != ""
						color: colors.red
						text: forgotPasswordPage.forgotPasswordPageError
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						id: forgotPasswordText
						visible: forgotPasswordPage.forgotPasswordTextV
						text: "Resetting password..."
					}
				}
				BackButton {}
			}
			StackPage {
				id: signUpPage
				topSpace: (1/8) * height
					
				onReload: {
					signUpTextV = false
					signUpButtonE = true
					signUpPageErrorMessage = ""
					signedUp = false
					signUpEmailField.text = ""
					signUpUsernameField.text = ""
					signUpPasswordField.text = ""
					confirmPasswordField.text = ""
				}
				property bool	signedUp: false
				property bool	signUpTextV: false
				property bool	signUpButtonE: true
				property string	signUpPageErrorMessage: ""
				
				Timer {
					id: signUpTimer
					interval: 10000
					onTriggered: if (stackView.currentItem == signUpPage) stackView.pop()
				}
				ColumnLayout {
					spacing: (1/20) * parent.height
					anchors.centerIn: parent
					id: signUpColumn
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: !signUpPage.signedUp ? qsTr("Welcome to MuseLab!") : qsTr("All Set!")
						font.pointSize: fontSizes.heading
					}
					StyledLabel {
						visible: signUpPage.signedUp
						font.bold: false
						text: qsTr("Follow the link sent to your email address to verify your account.")
					}
					GridLayout {
						visible: !signUpPage.signedUp
						id: signUpLayout
						rowSpacing: sizes.regSpacing + sizes.minSpacing
						columnSpacing: sizes.regSpacing
						anchors.horizontalCenter: parent.horizontalCenter
						columns: 2
						
						StyledLabel {text: "Email Address:"}
						
						StyledTextField {
							id: signUpEmailField
							implicitWidth: signUpPage.optionWidth
							placeholderText: "Enter email"
							maximumLength: 50
							Keys.onReturnPressed: signUpUsernameField.forceActiveFocus()
						}

						StyledLabel {text: "Username:"}
						
						StyledTextField {
							id: signUpUsernameField
							implicitWidth: signUpPage.optionWidth
							placeholderText: "Enter username"
							maximumLength: 20
							Keys.onReturnPressed: signUpPasswordField.forceActiveFocus()
						}

						StyledLabel {text: "Password:"}
						
						StyledTextField {
							id: signUpPasswordField
							implicitWidth: signUpPage.optionWidth
							placeholderText: "Enter password"
							echoMode: TextInput.Password
							maximumLength: 120
							Keys.onReturnPressed: confirmPasswordField.forceActiveFocus()
						}

						StyledLabel {text: "Confirm Password:"}
						
						StyledTextField {
							id: confirmPasswordField
							implicitWidth: signUpPage.optionWidth
							placeholderText: "Re-enter password"
							echoMode: TextInput.Password
							Keys.onReturnPressed: signUpButton.clicked()
						}
					}//GridLayout
					
					StyledButton {
						id: signUpButton
						anchors.horizontalCenter: parent.horizontalCenter
						text: "Sign Up"
						enabled: signUpPage.signUpButtonE
						visible: signUpPage.signedUp
						onClicked: {
							if (!(/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/g.test(signUpEmailField.text))) signUpPage.signUpPageErrorMessage = qsTr("Please enter a valid email.")
							else if (signUpUsernameField.text.length === "") signUpPage.signUpPageErrorMessage = qsTr("Please enter a username.")
							else if (signUpUsernameField.text.length < 3) signUpPage.signUpPageErrorMessage = qsTr("Username minimum length: 3 Characters")
							else if (signUpPasswordField.text.length === "") signUpPage.signUpPageErrorMessage = qsTr("Please enter a password.")
							else if (signUpPasswordField.text.length < 6) signUpPage.signUpPageErrorMessage = qsTr("Password minimum length: 6 Characters")
							else if (confirmPasswordField.text === "") signUpPage.signUpPageErrorMessage = qsTr("Please confirm your password.")
							else if (signUpPasswordField.text !== confirmPasswordField.text) signUpPage.signUpPageErrorMessage = qsTr("Passwords do not match.")
							else {
								signUpPage.signUpPageErrorMessage = ""
								signUpPage.signUpTextV = true
								signUpPage.signUpButtonE = false
								signUp(signUpUsernameField.text, signUpEmailField.text, signUpPasswordField.text)
							}
						}
					}//Button
				}
				ColumnLayout {
					spacing: sizes.regSpacing
					anchors {
						horizontalCenter: parent.horizontalCenter
						margins: sizes.regSpacing
						top: signUpColumn.bottom
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						visible: text != ""
						color: colors.red
						text: signUpPage.signUpPageErrorMessage
					}
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						id: signUpText
						visible: signUpPage.signUpTextV
						text: "Signing up..."
					}
				}
				BackButton {}
			}
			StackPage {
				id: projectPage
				topSpace: 40
					
				property var projectListModel: []
				
				onReload: {
					projectListCI = -1
					projectListE = false
					projectSelectButtonE = false
					projectSelectTextV = false
					useCodeButtonE = true
					useCodeFieldE = true
					useCodeTextV = false
					createProjectTextV = false
					createProjectButtonE = true
					projectPageErrorMessage = ""
					
					
					//rewrite this part for smoother compatibility with first launch
					projectPage.projectListModel = [{name: "Loading..."}]
					root.getProjects()
					
					//reset some vars from getProjectDetailsAndJoin
					//reload getProjects and reset combobox model
					
					//end socket
					//reset currentProjectId and currentProjectName
					//reset getProjectDetailsAndJoin
					//reset createProject
					if (root.currentSession != "") logOut()
				}
				//projectPage
				property int	projectListCI: -1
				property bool	projectListE: false
				property bool	projectSelectButtonE: false
				property bool	projectSelectTextV: false
				property bool	useCodeButtonE: true
				property bool	useCodeFieldE: true
				property bool	useCodeTextV: false
				property bool	createProjectTextV: false
				property bool 	createProjectButtonE: true
				property string	projectPageErrorMessage: ""
				
				Column {
					id: projectPageColumn
					spacing: sizes.maxSpacing
					anchors {
						centerIn: parent
						margins: sizes.maxSpacing
					}
					width: parent.width - (2 * anchors.margins)
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Hello") + " " + root.userName
						font.pointSize: fontSizes.heading
					}
					GridLayout {
						rowSpacing: sizes.maxSpacing
						columnSpacing: sizes.maxSpacing
						columns: 2
						anchors.horizontalCenter: parent.horizontalCenter
						width: Math.min(parent.width, 800)
						height: Math.min(projectPage.height / 2, 400)
						
						GridTile {
							Column {
								anchors.centerIn: parent
								spacing: sizes.maxSpacing
								width: parent.width - (2 * sizes.maxSpacing)
								
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									text: qsTr("Open Existing Project")
								}
								RowLayout {
									anchors.horizontalCenter: parent.horizontalCenter
									spacing: sizes.regSpacing
									width: parent.width
									
									StyledComboBox {
										id: projectList
										Layout.fillWidth: true
										popupItemWidth: width
										currentIndex: projectPage.projectListCI
										textRole: "name"
										model: projectPage.projectListModel
										enabled: projectPage.projectListE
										Keys.onReturnPressed: projectSelectButton.clicked()
										/*property var actModel: model.sort(function(a,b) {
											return a.projectId ? (b.projectId - a.projectId) : 0
										})
										onActModelChanged: if (model != actModel) model = actModel*/
									}
									StyledButton {
										id: projectSelectButton
										text: "Select"
										enabled: projectPage.projectSelectButtonE
										onClicked: {
											if (projectList.currentIndex > -1) {
												projectPage.projectSelectTextV = true
												projectPage.projectSelectButtonE = false
												projectPage.projectListE = false
												projectPage.useCodeButtonE = false
												projectPage.useCodeFieldE = false
												projectPage.createProjectButtonE = false
												projectPage.projectPageErrorMessage = ""
												root.currentProjectId = projectPage.projectListModel[projectList.currentIndex].projectId
												projectSelectSettings.projectId = projectPage.projectListModel[projectList.currentIndex].projectId
												root.currentProjectName = projectList.currentText //does this work??
												stackView.push(currentProjectPage)
												startSocket("")
												//insert projectSelectTextV = false where best suited
											} else projectPage.projectPageErrorMessage = "No project selected." //we shouldn't ever get here
										}//onClicked
									}
									Settings {
										id: projectSelectSettings
										category: "MuseLab Plugin"
										property var projectId: false
									}
								}//Row
									
								StyledLabel {
									id: projectSelectText
									anchors.horizontalCenter: parent.horizontalCenter
									text: "Loading Project '" + projectList.currentText + "'..."
									visible: projectPage.projectSelectTextV
									font.italic: true
								}
							}//column
						}
						GridTile {
							Column {
								anchors.centerIn: parent
								spacing: sizes.maxSpacing
								width: parent.width - (2 * sizes.maxSpacing)
								
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									text: "Use Join Code"
								}
								RowLayout {
									anchors.horizontalCenter: parent.horizontalCenter
									spacing: sizes.regSpacing
									width: parent.width
									
									StyledTextField {
										id: useCodeField
										Layout.fillWidth: true
										enabled: projectPage.useCodeFieldE
										placeholderText: "Enter Code"
										maximumLength: 8
										Keys.onReturnPressed: useCodeButton.clicked()
									}
									StyledButton {
										id: useCodeButton
										text: "Redeem"
										enabled: projectPage.useCodeButtonE
										onClicked: {
											if (useCodeField.text.length == 8) {
												projectPage.useCodeTextV = true
												projectPage.projectSelectButtonE = false
												projectPage.useCodeButtonE = false
												projectPage.useCodeFieldE = false
												projectPage.createProjectButtonE = false
												projectPage.projectPageErrorMessage = ""
												getProjectDetailsAndJoin(useCodeField.text)
												//insert projectSelectTextV = false where best suited=======================================
											} else projectPage.projectPageErrorMessage = "Please enter a valid code."
										}
									}
								}
								StyledLabel {
									id: useCodeText
									anchors.horizontalCenter: parent.horizontalCenter
									//REWRITE
									text: "Joining project..."
									visible: projectPage.useCodeTextV
									font.italic: true
								}
							}
						}
						GridTile {
							Column {
								anchors.centerIn: parent
								spacing: sizes.maxSpacing
								width: parent.width - (2 * sizes.maxSpacing)
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									text: "Create new Project"
								}
								RowLayout {
									anchors.horizontalCenter: parent.horizontalCenter
									spacing: sizes.regSpacing
									width: parent.width
									
									StyledTextField {
										id: createProjectField
										Layout.fillWidth: true
										placeholderText: "Enter title"
										maximumLength: 32
										Keys.onReturnPressed: createProjectButton.clicked()
									}
									StyledButton {
										id: createProjectButton
										text: "Create"
										enabled: projectPage.createProjectButtonE
										onClicked: {
											if (createProjectField.text == "") projectPage.projectPageErrorMessage = "Please enter a project name."
											else {
												projectPage.createProjectButtonE = false
												projectPage.createProjectTextV = true
												projectPage.projectPageErrorMessage = ""
												createProject(createProjectField.text)
											}
										}
									}//Button
								}//Row
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									id: createProjectText
									visible: projectPage.createProjectTextV
									text: "Creating project, please wait..."
									font.italic: true
								}
							}
						}
						GridTile {
							Column {
								anchors.centerIn: parent
								spacing: sizes.maxSpacing
								width: parent.width - (2 * sizes.maxSpacing)
								
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									text: qsTr("Manage Projects")
									
								}
								StyledButton {
									anchors.horizontalCenter: parent.horizontalCenter
									text: qsTr("Open Project Manager")
									onClicked: {
										stackView.push(projectManagerPage)
										projectManagerPage.getProjects()
									}
								}
							}
						}
					}//GridLayout
				}//Column
				StyledLabel {
					anchors {
						horizontalCenter: parent.horizontalCenter
						top: projectPageColumn.bottom
						topMargin: sizes.maxSpacing
					}
					visible: text != ""
					color: colors.red
					text: projectPage.projectPageErrorMessage
				}
				BackButton {}
			}
			StackPage {
				id: projectManagerPage
				
				function getProjects() {
					var request = new XMLHttpRequest()
					request.onreadystatechange = function() {
						if (request.readyState == XMLHttpRequest.DONE) {
							if (request.status === 200) {
								var response = request.responseText
								var json = JSON.parse(response)
								projectsRepeater.model = json
								projectTabView.visible = true
								//maybe refresh search here too
							}
						}
					}
					request.open("GET", getApiUrl("/projects/list"), true)
					request.setRequestHeader("Authorization", "Bearer " + root.token)
					request.send()
				}
				Column {
					spacing: sizes.maxSpacing
					visible: ! projectTabView.visible
					anchors.centerIn: parent
					
					StyledBusyIndicator {anchors.horizontalCenter: parent.horizontalCenter}
					
					StyledLabel {text: qsTr("Loading projects..."); font.italic: true}
				}
				Column {
					spacing: sizes.maxSpacing
					visible: projectTabView.visible && projectsRepeater.model.length < 1
					anchors {
						centerIn: parent
						verticalCenterOffset: - projectManagerRow.height / 2
					}
					StyledLabel {
						text: qsTr("No projects?")
						font.pointSize: fontSizes.title
						anchors.horizontalCenter: parent.horizontalCenter
					}
					StyledLabel {
						text: qsTr("To create a new project, click the 'New Project' button.")
						anchors.horizontalCenter: parent.horizontalCenter
					}
				}
				TabBar {
					id: projectTabView
					visible: false
					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
						margins: 3
						bottomMargin: 0
					}
					background: Rectangle {color: "transparent"}
					
					Repeater {
						id: projectsRepeater
						model: []
						property var actModel: model.sort(function(a,b) {
							return (b.projectId - a.projectId)
						})
						onActModelChanged: if (model != actModel) model = actModel
						StyledTabButton {text: projectsRepeater.model[index].name}
					}
				}
				StackLayout {
					id: projectMStack
					anchors {
						top: projectTabView.bottom
						bottom: projectManagerRow.top
						left: parent.left
						right: parent.right
					}
					currentIndex: projectTabView.currentIndex
					
					Repeater {
						model: projectsRepeater.model
						//move this item to separate component and reuse later
						Item {
							id: projectItem
							property var projectMTitle: projectsRepeater.model[index].name
							property var projectMId: projectsRepeater.model[index].projectId
							property var projectM: projectsRepeater.model[index]
							anchors.fill: parent
							Item {
								id: projectMTitleItem
								anchors {
									left: parent.left
									right: parent.right
									top: parent.top
								}
								height: Math.max(children[0].implicitHeight + (2 * sizes.regSpacing), 60)
								
								StyledLabel {
									anchors {
										centerIn: parent
										horizontalCenterOffset: - Math.max(0, (width - parent.width) / 2 + projectMButton.width + (2 * projectMButton.anchors.margins))
									}
									text: qsTr("Manage Project") + " '" + projectItem.projectMTitle + "'"
									font.pointSize: fontSizes.title
									property var maximumWidth: parent.width - projectMButton.width - (3 * projectMButton.anchors.margins)
									width: Math.min(maximumWidth, implicitWidth)
									wrapMode: Text.WordWrap
									horizontalAlignment: Text.AlignHCenter
								}
								IconMenuBox {
									id: projectMButton
									height: 36
									imgPadding: 9
									anchors {
										right: parent.right
										top: parent.top
										margins: sizes.regSpacing + sizes.minSpacing
									}
									background.height: sizes.controlHeight
										
									model: [{
											text: qsTr("Open Project"),
											action: "open-project"
										}, {
											text: qsTr("Edit Project Properties"),
											action: "edit-project"
										}, {
											text: qsTr("Leave Project"),
											action: "leave-project"
										}, {
											text: qsTr("Delete Project"),
											action: "delete-project"
										}, {
											text: qsTr("Manage Projects Online"),
											action: "manage-online"
										}
									]
									function trigger(action) {
										switch (action) {
											case "manage-online": {
												Qt.openUrlExternally("https://muselab.app/projects")
												projectMBackButton.clicked()
												break
											}
											case "edit-project": {
												projectInfoDialog.open()
												break
											}
											case "leave-project": {
												pluginWindow.confirmAction(("Are you sure you want to leave '" + projectItem.projectMTitle + "'?"
												+ "\n" + "You won't be able to rejoin unless you are reinvited."), function() {
													userListModel.removeUser(root.userName, 0)
												}, false)
												break
											}
											case "delete-project": {
												pluginWindow.confirmAction(("Are you sure you want to delete '" + projectItem.projectMTitle + "'?"
												+ "\n" + "Deleting projects is irreversible and all data will be lost."), function () {
													deleteProject(projectItem.projectMId, projectItem.projectMTitle)
												}, false)
												break
											}
											case "open-project": {
												if (projectItem.projectM.version == mscoreMajorVersion) {
													root.currentProjectId = projectItem.projectMId
													root.currentProjectName = projectItem.projectMTitle
													stackView.replace(projectManagerPage, currentProjectPage, StackView.PushTransition)
													startSocket("")
												} else {
													pluginWindow.confirmAction((projectItem.projectMTitle
														+ " was made in a different MuseScore version and can't be opened here."), function() {}, true)
												}
												break
											}
										}
									}
									function deleteProject(projectId, projectName) {
										var request = new XMLHttpRequest()
										request.onreadystatechange = function() {
											if (request.readyState == XMLHttpRequest.DONE) {
												if (request.status === 200) {
													debugLog(("Deleted project " + projectName), 1)
													var newModel = projectsRepeater.actModel
													newModel.splice(projectTabView.currentIndex, 1)
													projectsRepeater.model = newModel
												} else debugLog(("Failed to delete project!"), 2)
											}
										}
										request.open("DELETE", getApiUrl("/projects/delete/" + projectItem.projectMId), true)
										request.setRequestHeader("Content-Type", "application/json")
										request.setRequestHeader("Authorization", "Bearer "+root.token)
										request.send()
									}
								}
							}
							Item {
								anchors {
									left: parent.left
									right: parent.right
									top: projectMTitleItem.bottom
									bottom: parent.bottom
								}
								Rectangle {
									width: sizes.thinBorderWidth
									anchors {
										horizontalCenter: parent.horizontalCenter
										top: parent.top
										bottom: parent.bottom
										margins: sizes.regSpacing
									}
									color: colors.whiteText
									opacity: colors.styledOpacity
								}
								Item {
									anchors {
										left: parent.left
										right: parent.horizontalCenter
										top: parent.top
										bottom: parent.bottom
									}
									ProjectManagerSubHeading {
										id: userTitle
										text: qsTr("Users")
									}
									Item {
										anchors {
											left: parent.left
											right: parent.right
											top: userTitle.bottom
											bottom: parent.bottom
										}
										ProjectMList {
											anchors.bottom: addUser2Row.top
											id: userListModel
											model: projectItem.projectM.users
											actModel: model.sort(function(a,b) {
												return (a.id == root.userId) ? -1 : 0
											})
											removeEnabled: function(i) {
												return actModel[i].id != root.userId
											}
											displayText: function(i) {
												return actModel[i].username
											}
											onRemoveAction: function(i) {
												pluginWindow.confirmAction(("Remove " + userListModel.actModel[i].username
													+ " from '" + projectItem.projectMTitle + "'?"), function() {
													removeUser(userListModel.actModel[i].username, i)
												}, false)
											}
											function removeUser(name, index) {
												if (name == root.userName) debugLog(("Leaving project..."), 1)
												else debugLog(qsTr("Removing user..."), 1)
												if (name.length < 1) return debugLog("No username was entered!", 2)
												var check = false
												for (var i in userListModel.actModel) {
													if (userListModel.actModel[i].username == name) check = true
												}
												if (!check) return debugLog(("No user " + name + " in project"), 2)
												var content = {
													"username": name
												}
												var request = new XMLHttpRequest()
												request.onreadystatechange = function() {
													if (request.readyState == XMLHttpRequest.DONE) {
														if (request.status === 200) {
															debugLog(("Removed user " + name + " from project " + projectItem.projectMTitle), 1)
															var newModel = userListModel.actModel
															newModel.splice(index, 1)
															userListModel.model = newModel
															if (name == root.userName) {
																var newModel = projectsRepeater.actModel
																newModel.splice(projectTabView.currentIndex, 1)
																projectsRepeater.model = newModel
																//projectManagerPage.getProjects()
															}
														} else debugLog(qsTr("Failed to remove user!"), 2)
													}
												}
												request.open("POST", getApiUrl("/projects/" + projectItem.projectMId + "/remove/user"), true)
												request.setRequestHeader("Content-Type", "application/json")
												request.setRequestHeader("Authorization", "Bearer " + root.token)
												request.send(JSON.stringify(content))
											}
										}
										Item {
											id: addUser2Row
											anchors {
												margins: sizes.regSpacing
												left: parent.left
												right: parent.right
												bottom: parent.bottom
											}
											height: sizes.controlHeight
											width: parent.width
											//Component.onCompleted: height = childrenRect.height
											property var spacing: sizes.regSpacing
											
											StyledTextField {
												id: addUser2Field
												accented: false
												anchors {
													verticalCenter: parent.verticalCenter
													right: addUser2Button.left
													left: parent.left
													rightMargin: parent.spacing
												}
												placeholderText: qsTr("Add a new user...")
												Keys.onReturnPressed: {
													parent.addUser(text)
													text = ""
												}
											}
											
											StyledButton {
												id: addUser2Button
												text: qsTr("Add")
												anchors.verticalCenter: parent.verticalCenter
												onClicked: {
													parent.addUser(addUser2Field.text)
													addUser2Field.text = ""
												}
												anchors.right: parent.right
											}
											function addUser(name) {
												if (name.length < 1) return debugLog(qsTr("No username was entered!"), 2)
												else debugLog(("Adding " + name + " to project"), 1)
												for (var i in userListModel.actModel) {
													if (userListModel.actModel[i].username == name) return debugLog("User is already in project!", 2)
												}
												var content = {
													"username": name
												}
												var request = new XMLHttpRequest()
												request.onreadystatechange = function() {
													if (request.readyState == XMLHttpRequest.DONE) {
														if (request.status === 200) {
															var response = request.responseText
															var json = JSON.parse(response)
															var newModel = userListModel.actModel
															newModel.push(json)
															userListModel.model = newModel
															debugLog(("Added user " + name + " to project " + projectItem.projectMTitle), 1)
														} else debugLog(("Unable to find user " + name), 2)
													}
												}
												request.open("POST", getApiUrl("/projects/" + projectItem.projectMId + "/add/user"), true)
												request.setRequestHeader("Content-Type", "application/json")
												request.setRequestHeader("Authorization", "Bearer " + root.token)
												request.send(JSON.stringify(content))
											}
										}
									}
								}
								Item {
									anchors {
										left: parent.horizontalCenter
										right: parent.right
										top: parent.top
										bottom: parent.bottom
									}
									ProjectManagerSubHeading {
										id: fileTitle
										text: qsTr("Versions")
										IconButton {
											id: fileSort
											height: 36
											imgPadding: 9
											imgSource: "icons/sort.svg"
											anchors {
												right: parent.right
												verticalCenter: parent.verticalCenter
												margins: sizes.regSpacing + sizes.minSpacing
											}
											indicator.rotation: checked ? 180 : 0
											background {
												width: 30
												height: 30
												visible: false
											}
											checkable: true
											checked: true
											
											hoverEnabled: true
											StyledToolTip {
												text: qsTr("Sort files by creation date, in") + " "
												+ (parent.checked ? qsTr("ascending") : qsTr("descending")) + " " + qsTr("order")
											}
										}
									}
									Item {
										anchors {
											left: parent.left
											right: parent.right
											top: fileTitle.bottom
											bottom: parent.bottom
										}
										Flickable {
											id: fileListModel
											property var model: projectItem.projectM.files
											property var actModel: model.sort(function(a,b) {
													return (b.version - a.version) * (fileSort.checked ? 1 : -1)
												})
											signal removeAction(int index)
											clip: true
											anchors {
												margins: sizes.regSpacing
												left: parent.left
												right: parent.right
												top: parent.top
												bottom: addFileButton.top
											}
											property var removeEnabled: function(i) {
												return model.length > 1
											}
											property var displayText: function(i) {
												return actModel[i].fileName.slice(0, -5)//slice removes mscx appendage
											}
											ListView {
												id: listView
												anchors.fill: parent
												model: fileListModel.actModel
												delegate: AlternatingTile {
													height: sizes.controlHeight
													width: listView.width
													
													StyledLabel {
														font.bold: false
														anchors {
															left: parent.left
															leftMargin: sizes.minSpacing
															verticalCenter: parent.verticalCenter
														}
														text: fileListModel.displayText(index)
														width: parent.width - (2 * anchors.leftMargin) - (removeButton.width + removeButton.anchors.rightMargin)
														elide: Text.ElideRight
													}
													IconMenuBox {
														id: removeButton
														
														anchors {
															right: parent.right
															verticalCenter: parent.verticalCenter
														}
														model: fileListModel.model.length > 1 ? [{
																text: qsTr("Open File"),
																action: "open"
															}, {
																text: qsTr("Delete File"),
																action: "delete"
															}
														] : [{
																text: qsTr("Open File"),
																action: "open"
														}]
														function trigger(action) {
															switch (action) {
																case "delete": {
																	pluginWindow.confirmAction(("Delete file '" + fileListModel.actModel[index].fileName.slice(0, -5)
																		+ "' from " + projectItem.projectMTitle + "?" + "\r\n" + "This cannot be undone."), function () {
																			fileListModel.removeFile(fileListModel.actModel[index].id, index)
																		}, false)
																	break
																}
																case "open": {
																	root.currentProjectId = projectItem.projectMId
																	root.currentProjectName = projectItem.projectMTitle
																	stackView.replace(projectManagerPage, currentProjectPage, StackView.PushTransition)
																	var request = new XMLHttpRequest()
																	request.onreadystatechange = function() {
																		if (request.readyState == XMLHttpRequest.DONE) {
																			if (request.status === 200) {
																				var response = request.responseText
																				//var json = JSON.parse(response)
																				root.loadOlderFile = response
																				startSocket("")
																			}
																		}
																	}
																	request.open("GET", getApiUrl("/files/get/" + fileListModel.actModel[index].id), true)
																	request.setRequestHeader("Authorization", "Bearer " + root.token)
																	request.send()
																	break
																}
															}
														}
														function deleteProject(projectId, projectName) {
															var request = new XMLHttpRequest()
															request.onreadystatechange = function() {
																if (request.readyState == XMLHttpRequest.DONE) {
																	if (request.status === 200) {
																		debugLog(("Deleted project " + projectName), 1)
																		var newModel = projectsRepeater.actModel
																		newModel.splice(projectTabView.currentIndex, 1)
																		projectsRepeater.model = newModel
																	} else {
																		debugLog(("Failed to delete project!"), 2)
																	}
																}
															}
															request.open("DELETE", getApiUrl("/projects/delete/" + projectItem.projectMId), true)
															request.setRequestHeader("Content-Type", "application/json")
															request.setRequestHeader("Authorization", "Bearer "+root.token)
															request.send()
														}
													}
												}
												ScrollIndicator.vertical: ScrollIndicator {visible: listView.contentHeight > listView.height}
											}
											onRemoveAction: function(i) {
												pluginWindow.confirmAction(("Delete file '" + actModel[i].fileName.slice(0, -5)
													+ "' from " + projectItem.projectMTitle + "?" + "\r\n" + "This cannot be undone."), function () {
														removeFile(actModel[i].id, i)
													}, false)
												}
											function removeFile(fileId, index) {
												debugLog(qsTr("Removing file..."), 1)
												var request = new XMLHttpRequest()
												request.onreadystatechange = function() {
													if (request.readyState == XMLHttpRequest.DONE) {
														if (request.status === 200) {
															var newModel = fileListModel.actModel
															newModel.splice(index, 1)
															fileListModel.model = newModel
															debugLog(qsTr("Removed file!"), 1)
														} else {
															debugLog(qsTr("Unable to remove file"), 2)
														}
													}
												}
												request.open("DELETE", getApiUrl("/projects/get/" + projectMId + "/files/delete/" + fileId), true)
												request.setRequestHeader("Authorization", "Bearer " + root.token)
												request.send()
											}
										}
										StyledButton {
											id: addFileButton
											text: qsTr("Upload a new file")
											width: parent.width - 2 * anchors.margins
											anchors {
												horizontalCenter: parent.horizontalCenter
												margins: sizes.regSpacing
												bottom: parent.bottom
											}
											onClicked: {
												addFileDialog.folder = addFileSettings.folder
												addFileDialog.open()
											}
										}
										FileDialog {
											property var path: ""
											id: addFileDialog
											title: qsTr("Upload file to") + " " + projectItem.projectMTitle
											selectExisting:	true
											selectFolder:	false
											selectMultiple:	false
											folder: shortcuts.home
											nameFilters: [qsTr("Uncompressed MuseScore File (*.mscx)")] //displays file type in dialog window
											
											onAccepted: {
												addFileSettings.folder = folder
												path = addFileDialog.fileUrl.toString()
												path = path.replace(/^(file:\/{3})/,"") // remove prefixed "file:///"
												path = decodeURIComponent(path) // unescape html codes like '%23' for '#'
												uploadFile(path)
											}
											onRejected: {
												path = false
												debugLog("No file selected", 1)
											}
											function uploadFile(filePath) {
												debugLog("Uploading file...", 1)
												var fileName = getFileNameFromPath(filePath)
												uploadXMLFile.source = filePath
												var xhr = new XMLHttpRequest()
												xhr.onreadystatechange = function() {
													if (xhr.readyState === XMLHttpRequest.DONE) {
														if (xhr.status === 200) {
															debugLog("File uploaded!\nReloading project info", 1)
															root.getProject(projectItem.projectMId, function (json) {projectItem.projectM = json})
														} else debugLog("Unable to upload file", 2)
													}
												}
												var boundary = "---------------------------" + (new Date()).getTime().toString(16)
												var body = "--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="name"\r\n\r\n'
												body += fileName
												body += "\r\n--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="project_id"\r\n\r\n'
												body += projectMId
												body += "\r\n--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n'
												body += 'Content-Type: text/xml\r\n\r\n'
												body += uploadXMLFile.read()
												body += "\r\n--" + boundary
												xhr.open("POST", getApiUrl("/files/upload"))
												xhr.setRequestHeader("Authorization", "Bearer " + root.token)
												xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary)
												xhr.send(body)
											}
										}
										Settings {
											id: addFileSettings
											category: "MuseLab file picker"
											property var folder: addFileDialog.folder
										}
									}
								}
							}
						}
					}
				}
				Item {
					id: projectManagerRow
					visible: projectTabView.visible
					anchors {
						left: parent.left
						right: parent.right
						bottom: parent.bottom
					}
					height: 48
					
					Item {
						id: projectSearchItem
						height: parent.height
						anchors.horizontalCenter: parent.horizontalCenter
						enabled: projectsRepeater.model.length >= 1
						width: 240
						property var spacing: sizes.maxSpacing
						
						StyledComboBox {
							id: projectSearchField
							editable: true
							property var rawModel: projectsRepeater.model
							model: rawModel
							textRole: "name"
							anchors {
								verticalCenter: parent.verticalCenter
								left: parent.left
								margins: sizes.minSpacing
							}
							implicitWidth: parent.width - parent.spacing - projectSearchButton.width
							onActivated: accepted()
							onAccepted: {
								debugLog(("Searching for project " + editText), 1)
								for (var i in projectsRepeater.model) {
									if (projectsRepeater.model[i].name == editText) {
										debugLog(qsTr("Project found!"), 1)
										projectTabView.currentIndex = i
										editText = ""
										return
									}
								}
								debugLog(qsTr("Unable to find project"), 2)
							}
							contentItem: StyledTextField {
								text: projectSearchField.editText
								placeholderText: qsTr("Search...")
								accented: false
								background: Rectangle {color: "transparent"}
							}
							background: Rectangle {
								color: "transparent"
								border {
									color: colors.midGreen
									width:sizes.borderWidth
								}
								radius: sizes.minSpacing
							}
						}
						StyledButton {
							id: projectSearchButton
							//text: qsTr("Search")
							anchors {
								verticalCenter: parent.verticalCenter
								right: parent.right
								margins: sizes.minSpacing
							}
							implicitHeight: sizes.controlHeight
							implicitWidth: sizes.controlHeight
							contentItem: StyledIcon {
								anchors {
									fill: parent
									margins: sizes.minSpacing
									centerIn: parent
								}
								source: "assets/icons/search.svg"
							}
							onClicked: projectSearchField.accepted()
						}
					}
					StyledButton {
						id: createProject2Button
						text: qsTr("New Project")
						anchors {
							margins: sizes.regSpacing
							right: parent.right
							bottom: parent.bottom
						}
						onClicked: {
							createProjectDialog.open()
							createProjectDialog.forceActiveFocus()
						}
					}
				}
				StyledDialog {
					id: createProjectDialog
					title: qsTr("Create New Project")
					
					height: sizes.controlHeight + sizes.regSpacing + extraHeight
					width: 240
					
					StyledTextField {
						id: createProject2Field
						anchors {
							left: parent.left
							top: parent.top
						}
						implicitWidth: parent.width
						placeholderText: qsTr("Enter project title")
						maximumLength: 32
						Keys.onReturnPressed: createProjectDialog.accepted()
						Keys.onEscapePressed: createProjectDialog.rejected()
					}
					onOpened: createProject2Field.forceActiveFocus(Qt.PopupFocusReason) //doesnt work
					onAccepted: {
						debugLog(qsTr("Creating project..."), 1)
						var content = {
							"name": createProject2Field.text,
							"version": mscoreMajorVersion
						}
						var request = new XMLHttpRequest()
						request.onreadystatechange = function() {
							if (request.readyState == XMLHttpRequest.DONE) {
								if (request.status === 200) {
									debugLog(qsTr("Project created!"), 1)
									var response = request.responseText
									var json = JSON.parse(response)
									projectManagerPage.getProjects()
									//doesnt find the right project, probably need to wait
									for (var i in projectsRepeater.model) {
										if (projectsRepeater.model[i].id == json.id) {
											projectTabView.currentIndex = i
											return
										}
									}
								} else {
									//do something
									debugLog(qsTr("Unable to create project"), 2)
								}
							}
						}
						request.open("POST", getApiUrl("/projects/create"), true)
						request.setRequestHeader("Content-Type", "application/json")
						request.setRequestHeader("Authorization", "Bearer "+root.token)
						request.send(JSON.stringify(content))
						createProjectDialog.close()
					}
					onRejected: {
						createProject2Field.text = ""
						createProjectDialog.close()
					}
				}
				StyledDialog {
					id: projectInfoDialog
					height: projectInfoDialogColumn.height + sizes.regSpacing + extraHeight
					width: 360
					buttons: [qsTr("Save"), qsTr("Cancel")]
					Column {
						id: projectInfoDialogColumn
						spacing: sizes.maxSpacing
						anchors.margins: sizes.maxSpacing //useless probably
						width: parent.width
						StyledLabel {
							anchors.horizontalCenter: parent.horizontalCenter
							text: qsTr("Project Properties")
							font.pointSize: fontSizes.heading
						}
						GridLayout {
							columns: 2
							columnSpacing: sizes.regSpacing
							rowSpacing: sizes.regSpacing
							width: parent.width
							
							StyledLabel {text: qsTr("Title:")}
							
							EditProjectEditField {id: editProjectNameField}
							
							StyledLabel {text: qsTr("Ensemble:")}
							
							EditProjectEditField {id: editProjectEnsembleField}
							
							StyledLabel {text: qsTr("Genre:")}
							
							EditProjectEditField {id: editProjectGenreField}
							
							StyledLabel {text: qsTr("Created at:")}
							
							EditProjectStaticField {id: editProjectDateField}
							
							StyledLabel {text: qsTr("Created by:")}
							
							EditProjectStaticField {id: editProjectCreatedByField}
						}
					}
					onOpened: {
						editProjectNameField.text = projectsRepeater.model[projectTabView.currentIndex].name
						editProjectNameField.placeholderText = projectsRepeater.model[projectTabView.currentIndex].name
						editProjectEnsembleField.text = projectsRepeater.model[projectTabView.currentIndex].ensemble
						editProjectEnsembleField.placeholderText = projectsRepeater.model[projectTabView.currentIndex].ensemble
						editProjectGenreField.text = projectsRepeater.model[projectTabView.currentIndex].genre
						editProjectGenreField.placeholderText = projectsRepeater.model[projectTabView.currentIndex].genre
						editProjectCreatedByField.text = projectsRepeater.model[projectTabView.currentIndex].createdBy.username
						editProjectDateField.text = Utils.formatProjectDate(projectsRepeater.model[projectTabView.currentIndex].date)
					}
					onAccepted: {
						var content = {
							"name": editProjectNameField.text,
							"genre": editProjectGenreField.text,
							"ensemble": editProjectEnsembleField.text
						}
						var match = true
						for (var i in Object.keys(content)) {
							if (projectsRepeater.model[projectTabView.currentIndex][Object.keys(content)[i]] != content[Object.keys(content)[i]]) match = false
						}
						if (match) return debugLog(("Old info is the same as new info, not editing"), 1)
						var request = new XMLHttpRequest()
						request.onreadystatechange = function() {
							if (request.readyState == XMLHttpRequest.DONE) {
								if (request.status === 200) {
									debugLog(("Edited info for project " + content.name + ".\r\nReloading projects..."), 2)
									root.getProject(projectsRepeater.model[projectTabView.currentIndex].projectId, function (json) {
										var newModel = projectsRepeater.model
										newModel[projectTabView.currentIndex] = json
										projectsRepeater.model = newModel
									})
								} else {
									debugLog(qsTr("Unable to edit project"), 2)
									opened()
								}
							}
						}
						request.open("POST", getApiUrl("/projects/update/" + projectsRepeater.model[projectTabView.currentIndex].projectId), true)
						request.setRequestHeader("Content-Type", "application/json")
						request.setRequestHeader("Authorization", "Bearer " + root.token)
						request.send(JSON.stringify(content))
					}
				}
				BackButton {id: projectMBackButton}
			}
			StackPage {
				id: currentProjectPage
				topSpace: (1/20) * height
					
				property var currentProjectObj: {files: [{fileName: qsTr("Loading files...")}]}
				
				onReload: {
					root.log = [{text: qsTr("Loading Score, please wait..."), initial: true}]
					root.getProject(root.currentProjectId, function (json) {currentProjectObj = json})
				}
				onCurrentProjectObjChanged: cppStack.currentIndexChanged()
				
				MouseArea {
					anchors.fill: parent
					cursorShape: cppMouseArea.dragging ? Qt.SizeHorCursor : Qt.ArrowCursor
				}
				Column {
					spacing: sizes.maxSpacing
					anchors {
						top: parent.top
						right: parent.right
						left: parent.left
					}
					height: parent.height - (2 * sizes.regSpacing) - cppBackButton.height
					
					Item {
						height: (2/3) * parent.height
						width: parent.width
						
						Item {
							clip: true
							anchors {
								top: parent.top
								right: cppInfoItem.left
								left: parent.left
								bottom: parent.bottom
							}
							Item {
								id: projectLogTitleItem
								anchors {
									left: parent.left
									right: parent.right
									top: parent.top
								}
								height: Math.max(children[0].implicitHeight + (2 * sizes.regSpacing), 60)
								
								StyledLabel {
									anchors.centerIn: parent
									text: (qsTr("Chat with") + " " + root.currentProjectName)
									font.pointSize: fontSizes.subheading
									width: Math.min(parent.width - (2 * sizes.maxSpacing), implicitWidth)
									wrapMode: Text.WordWrap
									horizontalAlignment: Text.AlignHCenter
									verticalAlignment: Qt.AlignVCenter
								}
							}
							ListView {
								id: logListView
								anchors {
									top: projectLogTitleItem.bottom
									left: parent.left
									right: parent.right
									bottom: sendField.top
									margins: sizes.maxSpacing
									topMargin: 0
								}
								width: parent.width
								clip: true
								model: root.log
								delegate: AlternatingTile {
									height: Math.max(children[1].implicitHeight, sizes.controlHeight) //doesnt get smaller, probably because of tile
									width: logListView.width
									
									StyledLabel {
										font.bold: false
										anchors {
											left: parent.left
											margins: sizes.minSpacing
											verticalCenter: parent.verticalCenter
										}
										text: logListView.model[index].text
										width: parent.width - 2 * anchors.leftMargin
										wrapMode: Text.WordWrap
										elide: Text.ElideRight
									}
								}
								ScrollIndicator.vertical: ScrollIndicator {visible: logListView.contentHeight > logListView.height}
								onCountChanged: positionViewAtEnd()
							}
							StyledTextField {
								id: sendField
								anchors {
									horizontalCenter: parent.horizontalCenter
									margins: sizes.maxSpacing
									bottom: parent.bottom
									bottomMargin: 0
								}
								implicitWidth: parent.width - (2 * anchors.margins)
								text: ""
								placeholderText: ("Message " + currentProjectName + "...")
								Keys.onReturnPressed: {
									if (text != "" && !root.log[0].initial) {
										sendMessage(text)
										text = ""
									}
								}
							}//StyledTextField
						}
						Item {
							id: cppInfoItem
							anchors {
								top: parent.top
								right: parent.right
								bottom: parent.bottom
							}
							width: cppMouseArea.widthX
							
							MouseArea {
								id: cppMouseArea
								property var widthX: (1/3) * root.width + (width / 2)
								property bool dragging: false
								onPressed: dragging = containsMouse
								onMouseXChanged: if (dragging) widthX -= Math.floor(mouseX - (width / 2))
								//to-do: disallow dragging to offscreen
								onReleased: dragging = false
								anchors {
									left: parent.left
									top: parent.top
									bottom: parent.bottom
								}
								width: 5
								cursorShape: Qt.SizeHorCursor
								Rectangle {
									height: parent.height
									anchors.centerIn: parent
									width: sizes.thinBorderWidth
									color: colors.whiteText
								}
							}
							Item {
								clip: true
								anchors {
									top: parent.top
									right: parent.right
									bottom: parent.bottom
									left: cppMouseArea.right
								}
								TabBar {
									id: cppTabView
									anchors {
										left: parent.left
										right: parent.right
										top: parent.top
										margins: 3
										bottomMargin: 0
									}
									background: Rectangle {color: "transparent"}
									
									Repeater {
										id: cppRepeater
										model: [{text: qsTr("Users")}, {text: qsTr("Files")}, {text: qsTr("Info")}]
										
										StyledTabButton {
											text: cppRepeater.model[index].text
											width: (cppTabView.width - (2 * cppTabView.anchors.margins)) / cppRepeater.model.length
											contentItem.width: Math.min(contentItem.implicitWidth, width - sizes.minSpacing)
										}
									}
								}
								StackLayout {
									id: cppStack
									anchors {
										top: cppTabView.bottom
										bottom: parent.bottom
										left: parent.left
										right: parent.right
									}
									currentIndex: cppTabView.currentIndex
									onCurrentIndexChanged: if (currentIndex != -1) children[currentIndex].opened()
									
									Item {
										anchors.fill: parent
										signal opened
										
										Item {
											id: cppUsersTitleItem
											anchors {
												left: parent.left
												right: parent.right
												top: parent.top
											}
											height: Math.max(children[0].implicitHeight + (2 * sizes.regSpacing), 60)
											
											StyledLabel {
												anchors.centerIn: parent
												text: qsTr("Users Online")
												font.pointSize: fontSizes.subheading
												width: Math.min(parent.width - (2 * sizes.maxSpacing), implicitWidth)
												wrapMode: Text.WordWrap
												horizontalAlignment: Text.AlignHCenter
												verticalAlignment: Qt.AlignVCenter
											}
										}
										ListView {
											id: cppUsersList
											anchors {
												top: cppUsersTitleItem.bottom
												left: parent.left
												right: parent.right
												bottom: addUserButton.top
												margins: sizes.maxSpacing
												topMargin: 0
											}
											width: parent.width
											clip: true
											model: [{username: "Loading online users..."}]
											delegate: AlternatingTile {
												height: Math.max(childrenRect.height, sizes.controlHeight)
												width: cppUsersList.width
												
												StyledLabel {
													font.bold: false
													anchors {
														left: parent.left
														margins: sizes.minSpacing
														verticalCenter: parent.verticalCenter
													}
													text: cppUsersList.model[index].username
													width: parent.width - 2 * anchors.leftMargin
													wrapMode: Text.WordWrap
													elide: Text.ElideRight
												}
											}
											ScrollIndicator.vertical: ScrollIndicator {visible: cppUsersList.contentHeight > cppUsersList.height}
											onCountChanged: positionViewAtEnd()
										}
										StyledButton {
											id: addUserButton
											anchors {
												horizontalCenter: parent.horizontalCenter
												margins: sizes.maxSpacing
												bottom: parent.bottom
												bottomMargin: 0
											}
											implicitWidth: parent.width - (2 * anchors.margins)
											text: qsTr("Invite Users...")
											//enabled: !root.log[0].initial not working
											onClicked: {
												generateInviteCode()
												addUserDialog.open()
											}
											contentItem.width: Math.min(contentItem.implicitWidth, implicitWidth - sizes.minSpacing)
										}
									}
									Item {
										anchors.fill: parent
										signal opened
										
										Item {
											id: cppFilesTitleItem
											anchors {
												left: parent.left
												right: parent.right
												top: parent.top
											}
											height: Math.max(children[0].implicitHeight + (2 * sizes.regSpacing), 60)
											
											StyledLabel {
												anchors.centerIn: parent
												text: qsTr("Project Files")
												font.pointSize: fontSizes.subheading
												width: Math.min(parent.width - (2 * sizes.maxSpacing), implicitWidth)
												wrapMode: Text.WordWrap
												horizontalAlignment: Text.AlignHCenter
												verticalAlignment: Qt.AlignVCenter
											}
										}
										ListView {
											id: cppFilesList
											anchors {
												top: cppFilesTitleItem.bottom
												left: parent.left
												right: parent.right
												bottom: cppAddFileButton.top
												margins: sizes.maxSpacing
												topMargin: 0
											}
											width: parent.width
											clip: true
											model: currentProjectPage.currentProjectObj.files
											delegate: AlternatingTile {
												height: Math.max(childrenRect.height, sizes.controlHeight)
												width: cppFilesList.width
												
												StyledLabel {
													font.bold: false
													anchors {
														left: parent.left
														margins: sizes.minSpacing
														verticalCenter: parent.verticalCenter
													}
													text: cppFilesList.model[index].fileName.slice(0, -5)
													width: parent.width - 2 * anchors.leftMargin - cppFileOptionButton.width
													wrapMode: Text.WordWrap
													elide: Text.ElideRight
												}
												IconMenuBox {
													id: cppFileOptionButton
													
													anchors {
														right: parent.right
														verticalCenter: parent.verticalCenter
													}
													model: cppFilesList.model.length > 1 ? [{
															text: qsTr("Open File"),
															action: "open"
														}, {
															text: qsTr("Delete File"),
															action: "delete"
														}
													] : [{
															text: qsTr("Open File"),
															action: "open"
													}]
													function trigger(action) {
														switch (action) {
															case "delete": {
																pluginWindow.confirmAction(("Delete file '" + cppFilesList.model[index].fileName.slice(0, -5)
																	+ "' from " + root.currentProjectName + "?" + "\r\n" + "This cannot be undone."), function () {
																		cppFilesList.removeFile(cppFilesList.model[index].id, index)
																	}, false)
																break
															}
															case "open": {
																var request = new XMLHttpRequest()
																request.onreadystatechange = function() {
																	if (request.readyState == XMLHttpRequest.DONE) {
																		if (request.status === 200) {
																			var response = request.responseText
																			//var json = JSON.parse(response)
																			root.loadOlderFile = response
																			MSI.handleSync("")
																		}
																	}
																}
																request.open("GET", getApiUrl("/files/get/" + cppFilesList.model[index].id), true)
																request.setRequestHeader("Authorization", "Bearer " + root.token)
																request.send()
																break
															}
														}
													}
												}
											}
											ScrollIndicator.vertical: ScrollIndicator {visible: cppFilesList.contentHeight > cppFilesList.height}
											onCountChanged: positionViewAtBeginning()
											
											function removeFile(fileId, index) {
												debugLog(qsTr("Removing file..."), 1)
												var request = new XMLHttpRequest()
												request.onreadystatechange = function() {
													if (request.readyState == XMLHttpRequest.DONE) {
														if (request.status === 200) {
															var newModel = cppFilesList.model
															newModel.splice(index, 1)
															cppFilesList.model = newModel
															debugLog(qsTr("Removed file!"), 1)
														} else {
															debugLog(qsTr("Unable to remove file"), 2)
														}
													}
												}
												request.open("DELETE", getApiUrl("/projects/get/" + root.currentProjectId + "/files/delete/" + fileId), true)
												request.setRequestHeader("Authorization", "Bearer " + root.token)
												request.send()
											}
										}
										StyledButton {
											id: cppAddFileButton
											anchors {
												horizontalCenter: parent.horizontalCenter
												margins: sizes.maxSpacing
												bottom: parent.bottom
												bottomMargin: 0
											}
											implicitWidth: parent.width - (2 * anchors.margins)
											text: qsTr("Upload File")
											enabled: root.canSave//!root.log[0].initial not working
											contentItem.width: Math.min(contentItem.implicitWidth, implicitWidth - sizes.minSpacing)
											
											onClicked: {
												cppAddFiles.folder = cppAddFileSettings.folder
												cppAddFiles.open()
											}
										}
										FileDialog {
											property var path: ""
											id: cppAddFiles
											title: qsTr("Upload file to") + " " + root.currentProjectName
											selectExisting:	true
											selectFolder:	false
											selectMultiple:	false
											folder: shortcuts.home
											nameFilters: [qsTr("Uncompressed MuseScore File (*.mscx)")] //displays file type in dialog window
											
											onAccepted: {
												cppAddFileSettings.folder = folder
												path = cppAddFiles.fileUrl.toString()
												path = path.replace(/^(file:\/{3})/,"") // remove prefixed "file:///"
												path = decodeURIComponent(path) // unescape html codes like '%23' for '#'
												uploadFile(path)
											}
											onRejected: {
												path = false
												debugLog("No file selected", 1)
											}
											function uploadFile(filePath) {
												debugLog("Uploading file...", 1)
												var fileName = getFileNameFromPath(filePath)
												uploadXMLFile.source = filePath
												var fileContents = uploadXMLFile.read()
												var xhr = new XMLHttpRequest()
												xhr.onreadystatechange = function() {
													if (xhr.readyState === XMLHttpRequest.DONE) {
														if (xhr.status === 200) {
															debugLog("File uploaded!\nReloading project info", 1)
															root.getProject(root.currentProjectId, function (json) {
																currentProjectPage.currentProjectObj = json
																root.loadOlderFile = fileContents
																MSI.handleSync("uploaded")
															})
														} else debugLog("Unable to upload file", 2)
													}
												}
												var boundary = "---------------------------" + (new Date()).getTime().toString(16)
												var body = "--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="name"\r\n\r\n'
												body += fileName
												body += "\r\n--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="project_id"\r\n\r\n'
												body += root.currentProjectId
												body += "\r\n--" + boundary + "\r\n"
												body += 'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n'
												body += 'Content-Type: text/xml\r\n\r\n'
												body += fileContents
												body += "\r\n--" + boundary
												xhr.open("POST", getApiUrl("/files/upload"))
												xhr.setRequestHeader("Authorization", "Bearer " + root.token)
												xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary)
												xhr.send(body)
											}
										}
										Settings {
											id: cppAddFileSettings
											category: "MuseLab file picker"
											property var folder: cppAddFiles.folder
										}
									}
									Item {
										anchors.fill: parent
										signal opened
										signal accepted
										
										Item {
											id: cppInfoTitleItem
											anchors {
												left: parent.left
												right: parent.right
												top: parent.top
											}
											height: Math.max(children[0].implicitHeight + (2 * sizes.regSpacing), 60)
											
											StyledLabel {
												anchors.centerIn: parent
												text: qsTr("About") + " " + root.currentProjectName
												font.pointSize: fontSizes.subheading
												width: Math.min(parent.width - (2 * sizes.maxSpacing), implicitWidth)
												wrapMode: Text.WordWrap
												horizontalAlignment: Text.AlignHCenter
												verticalAlignment: Qt.AlignVCenter
											}
										}
										ScrollView {
											anchors {
												top: cppInfoTitleItem.bottom
												left: parent.left
												right: parent.right
												bottom: cppUpdateProjectButton.top
												margins: sizes.maxSpacing
												topMargin: 0
												rightMargin: anchors.margins - 12
											}
											clip: true
											contentWidth: availableWidth - 12
											
											GridLayout {
												columns: (width > (3/2) * sizes.optionWidth) ? 2 : 1
												columnSpacing: sizes.regSpacing
												rowSpacing: sizes.regSpacing
												width: parent.width
												anchors.horizontalCenter: parent.horizontalCenter
												
												StyledLabel {text: qsTr("Title:"); anchors.horizontalCenter: parent.columns == 1 ? parent.horizontalCenter : undefined}
												
												EditProjectEditField {id: cppProjectNameField; Keys.onReturnPressed: cppProjectEnsembleField.forceActiveFocus()}
												
												StyledLabel {text: qsTr("Ensemble:"); anchors.horizontalCenter: parent.columns == 1 ? parent.horizontalCenter : undefined}
												
												EditProjectEditField {id: cppProjectEnsembleField; Keys.onReturnPressed: cppProjectGenreField.forceActiveFocus()}
												
												StyledLabel {text: qsTr("Genre:"); anchors.horizontalCenter: parent.columns == 1 ? parent.horizontalCenter : undefined}
												
												EditProjectEditField {id: cppProjectGenreField; Keys.onReturnPressed: cppUpdateProjectButton.clicked()}
												
												StyledLabel {text: qsTr("Created at:"); anchors.horizontalCenter: parent.columns == 1 ? parent.horizontalCenter : undefined}
												
												EditProjectStaticField {id: cppProjectDateField}
												
												StyledLabel {text: qsTr("Created by:"); anchors.horizontalCenter: parent.columns == 1 ? parent.horizontalCenter : undefined}
												
												EditProjectStaticField {id: cppProjectCreatedByField}
											}
										}
										StyledButton {
											id: cppUpdateProjectButton
											anchors {
												horizontalCenter: parent.horizontalCenter
												margins: sizes.maxSpacing
												bottom: parent.bottom
												bottomMargin: 0
											}
											implicitWidth: parent.width - (2 * anchors.margins)
											text: qsTr("Update Project")
											contentItem.width: Math.min(contentItem.implicitWidth, implicitWidth - sizes.minSpacing) //standardise??
											
											onClicked: parent.accepted()
										}
										onOpened: {
											cppProjectNameField.text = currentProjectPage.currentProjectObj.name
											cppProjectNameField.placeholderText = currentProjectPage.currentProjectObj.name
											cppProjectEnsembleField.text = currentProjectPage.currentProjectObj.ensemble
											cppProjectEnsembleField.placeholderText = currentProjectPage.currentProjectObj.ensemble
											cppProjectGenreField.text = currentProjectPage.currentProjectObj.genre
											cppProjectGenreField.placeholderText = currentProjectPage.currentProjectObj.genre
											cppProjectCreatedByField.text = currentProjectPage.currentProjectObj.createdBy.username
											cppProjectDateField.text = Utils.formatProjectDate(currentProjectPage.currentProjectObj.date)
										}
										onAccepted: {
											var content = {
												"name": cppProjectNameField.text,
												"genre": cppProjectGenreField.text,
												"ensemble": cppProjectEnsembleField.text
											}
											var match = true
											for (var i in Object.keys(content)) {
												if (currentProjectPage.currentProjectObj[Object.keys(content)[i]] != content[Object.keys(content)[i]]) match = false
											}
											if (match) return debugLog(("Old info is the same as new info, not editing"), 1)
											var request = new XMLHttpRequest()
											request.onreadystatechange = function() {
												if (request.readyState == XMLHttpRequest.DONE) {
													if (request.status === 200) {
														debugLog(("Edited info for project " + content.name + ".\r\nReloading projects..."), 1)
														root.getProject(currentProjectPage.currentProjectObj.projectId, function (json) {
															currentProjectPage.currentProjectObj = json
															root.currentProjectName = currentProjectPage.currentProjectObj.name
														})
													} else {
														debugLog(("Unable to edit project"), 2)
														opened()
													}
												}
											}
											request.open("POST", getApiUrl("/projects/update/" + currentProjectPage.currentProjectObj.projectId), true)
											request.setRequestHeader("Content-Type", "application/json")
											request.setRequestHeader("Authorization", "Bearer " + root.token)
											request.send(JSON.stringify(content))
										}
									}
								}
							}
						}
					}
					RowLayout {
						spacing: sizes.maxSpacing
						width: parent.width - 2 * anchors.margins
						height: (1/3) * parent.height - parent.spacing
						anchors {
							margins: sizes.maxSpacing
							horizontalCenter: parent.horizontalCenter
						}
						clip: true
						
						StyledTile {
							Layout.fillWidth: true
							radius: sizes.regSpacing
							height: Math.max((children[1].height + 2 * sizes.regSpacing), parent.height)
							//height: parent.implicitHeight
							
							Column {
								spacing: sizes.regSpacing
								width: parent.width
								anchors.centerIn: parent
								
								StyledLabel {text: qsTr("Score Tools"); anchors.horizontalCenter: parent.horizontalCenter}
								
								GridLayout {
									columns: 3
									rowSpacing: sizes.regSpacing
									columnSpacing: sizes.regSpacing
									anchors.horizontalCenter: parent.horizontalCenter
									
									ToolbarButton {
										text: qsTr("Measures")
										enabled: false
										onClicked: addMeasuresDialog.open()
										imgsource: "assets/icons/measure.svg"
									}
									Repeater {
										id: toolbarRepeater
										model: [
											{text: qsTr("Crescendo"),	cmd: "hairpin",			imgsource: "assets/icons/cresc.svg"},
											{text: qsTr("Decrescendo"),	cmd: "hairpin-reverse",	imgsource: "assets/icons/decresc.svg"},
											{text: qsTr("Slur"),		cmd: "slur",			imgsource: "assets/icons/slur-alternate-2.svg"},
											{text: qsTr("8va"),			cmd: "8va",				imgsource: "assets/icons/8va.svg"},
											{text: qsTr("8vb"),			cmd: "8vb",				imgsource: "assets/icons/8vb.svg"}
										]
										ToolbarButton {
											text: toolbarRepeater.model[index].text
											onClicked: MSI.getSpanner(toolbarRepeater.model[index].cmd)
											imgsource: toolbarRepeater.model[index].imgsource
										}
									}
								}
							}
						}
						StyledTile {
							Layout.fillWidth: true
							radius: sizes.regSpacing
							height: Math.max((children[1].height + 2 * sizes.regSpacing), parent.height)
							
							Column {
								spacing: sizes.regSpacing
								width: parent.width
								anchors.centerIn: parent
								
								StyledLabel {text: qsTr("Project Tools"); anchors.horizontalCenter: parent.horizontalCenter}
								
								GridLayout {
									columnSpacing: sizes.regSpacing
									rowSpacing: sizes.regSpacing
									anchors.horizontalCenter: parent.horizontalCenter
									columns: 3
									
									StyledButton {
										text: qsTr("Reload")
										Layout.fillWidth: true
										enabled: root.currentProjectOpen
										onClicked: if (root.missingLatestChanges) {
											root.getRecentChanges()
											root.missingLatestChanges = false
										}
									}
									StyledButton {
										text: qsTr("Resync")
										Layout.fillWidth: true
										enabled: root.canSave && root.currentProjectOpen
										onClicked: queueChanges({data: [{}], sendScore: true})
									}
									StyledButton {
										text: qsTr("Save")
										Layout.fillWidth: true
										enabled: root.canSave && root.currentProjectOpen
										onClicked: saveScore()
									}
									StyledButton {
										text: qsTr("Send Feedback")
										Layout.fillWidth: true
										Layout.columnSpan: 2
										onClicked: root.sendFeedback(root.currentProjectId, root.errorLog)
									}
									StyledButton {
										text: qsTr("Quit")
										Layout.fillWidth: true
										onClicked: {
											logOut()
											smartQuit()
										}
									}
								}
							}
						}
					}
				}
				BackButton {id: cppBackButton}
				
				StyledDialog {
					id: addMeasuresDialog
					buttons: [qsTr("Append Measures"), qsTr("Insert Measures"), qsTr("Cancel")]
					height: addMeasuresRow.height + sizes.regSpacing + extraHeight
					width: Math.max(buttonsRow.width, addMeasuresRow.width) + extraWidth
					
					function actions (index) {
						switch (index) {
							case 0: {
								getMeasures("append", addMeasuresBox.value)
								break
							}
							case 1: {
								getMeasures("insert", addMeasuresBox.value)
								break
							}
						}
						close()
					}
					RowLayout {
						id: addMeasuresRow
						spacing: sizes.regSpacing
						
						StyledLabel {text: qsTr("Add")}
						
						StyledSpinBox {
							id: addMeasuresBox
							from: 1
							to: 1000
							stepSize: 1
							editable: true
							value: 1
						}
						StyledLabel {text: qsTr("measures")}
					}
				}
			}
			StackPage {
				id: whatsNewPage
				
				Item {
					anchors.fill: parent
					
					Column {
						spacing: (1/20) * parent.height
						y: whatsNewPage.topSpace
						anchors.horizontalCenter: parent.horizontalCenter
						
						StyledLabel {
							anchors.horizontalCenter: parent.horizontalCenter
							text: qsTr("Whats New")
							font.pointSize: fontSizes.heading
						}
						StyledLabel {
							textFormat: TextEdit.RichText
							text: changelog
						}
					}
					BackButton {}
				}//Item
			}
			StackPage {
				id: aboutPage
				topSpace: (1/10) * height
				
				Item {
					id: aboutItem
					anchors {
						top: parent.top
						topMargin: aboutPage.topSpace
						horizontalCenter: parent.horizontalCenter
					}
					height: parent.height - sizes.controlHeight - anchors.topMargin
					width: (3/4) * parent.width
					
					ScrollView {
						anchors.fill: parent
						clip: true
						
						Column {
							id: aboutColumn
							spacing: (1/20) * aboutPage.height
							anchors.left: parent.left
							width: aboutItem.width - (implicitHeight > aboutItem.height ? 12 : 0)
							
							Repeater {
								id: aboutRepeater
								model: [
									qsTr("About MuseLab"),
									qsTr("Welcome to MuseLab! MuseLab is a free extension for MuseScore 3 that lets users collaborate in real time."),
									qsTr("Users & projects"),
									qsTr("To get started, you'll first need to create a new project. This will create a blank score, and you can already start writing!" + "\n" +
									"It might get lonely, so you can invite other users using the 'Invite Users' button. From there, you can either invite someone as a guest using a one-time invite code, or add them to the project permanently." + "\n" +
									"You can remove users from a project via the Project Manager."),
									qsTr("Writing a score"),
									qsTr("MuseLab will automatically add and remove notes, rests, dynamics, ties, text, tuplets, and articulations." + "\n" +
									"Some objects, such as hairpins or slurs, can be added via the Toolbar instead of the palette." + "\n" +
									"For other changes, you can press the 'Resync' button, and your version of the score will be sent to all other users." + "\n" +
									"If you think you're missing some changes, press the 'Reload' button."),
									qsTr("Saving & Managing projects"),
									qsTr("MuseLab does not automatically save your work. Instead, you can press the 'Save' button. If you have unsaved changes, you will be prompted to save them when closing a project." + "\n" +
									"Additionally, MuseLab hosts a copy of each saved score, so you can retrieve older versions of a project if needed." + "\n" +
									"In the Project Manager you can see an overview of all files and users in your project, and can make any wanted changes." + "\n" +
									"The website (muselab.app) has similiar capabilities."),
									qsTr("MuseScore 4 Compatibility"),
									qsTr("MuseLab does not yet work with MuseScore 4, as its plugin API is missing some features essential for MuseLab to function." + "\n" + 
									"Support is planned as soon as is possible!")
								]
								StyledLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									width: Math.min(implicitWidth, aboutColumn.width)
									text: aboutRepeater.model[index]
									font.bold: Utils.isEven(index)
									font.pointSize: index == 0 ? fontSizes.heading : fontSizes.regular
									wrapMode: Text.WordWrap
								}
							}
						}
					}
				}
				BackButton {}
			}
			StackPage {
				id: creditsPage
				topSpace: (1/10) * height
				
				Column {
					//add scrollview later if needed
					id: creditColumn
					spacing: (1/20) * parent.height
					anchors {
						top: parent.top
						topMargin: creditsPage.topSpace
						margins: sizes.regSpacing
					}
					width: parent.width - (2 * anchors.margins)
					
					StyledLabel {
						anchors.horizontalCenter: parent.horizontalCenter
						text: qsTr("Credits")
						font.pointSize: fontSizes.title
					}
					Repeater {
						id: creditRepeater
						model: [
							{title: "Authxero",		imgsource: "assets/muselab/authxero.jpg", text: qsTr("Concept, server & installers")},
							{title: "XiaoMigros",	imgsource: "assets/muselab/xiaomigros.png", text: qsTr("Plugin design & MuseScore integration")},
							{title: "RZ Music",		imgsource: "assets/muselab/rz-music.png", text: qsTr("Website design")}
						]
						CreditBlock {
							width: Math.round (2/3 * creditColumn.width)
							height: 90
							title: creditRepeater.model[index].title
							imgsource: creditRepeater.model[index].imgsource
							text: creditRepeater.model[index].text
							rightAligned: !Utils.isEven(index)
							anchors.horizontalCenter: creditColumn.horizontalCenter
						}
					}
				}
				BackButton {}
			}
		}//StackView
		
		onClosing: {
			if (root.currentSession != "") logOut()
			debugLog(qsTr("Closing Muselab..."), 3)
			smartQuit()
		}
		
		function confirmAction(text, func, noCancel) {
			confirmDialog.text = text
			confirmDialog.action = func
			if (noCancel) {
				confirmDialog.buttons = [qsTr("OK")]
			} else {
				confirmDialog.buttons = [qsTr("OK"), qsTr("Cancel")]
			}
			confirmDialog.open()
		}
		StyledDialog {
			id: confirmDialog
			property var action
			property var text: ""
			width: Math.min((1/2) * parent.width, 480)
			height: label.implicitHeight + sizes.regSpacing + extraHeight
			
			StyledLabel {
				id: label
				text: confirmDialog.text
				width: parent.width
				wrapMode: Text.WordWrap				
			}
			onAccepted: confirmDialog.action()
		}
		StyledDialog {
			id: addUserDialog
			title: qsTr("Add Users to ") + currentProjectName
			buttons: [qsTr("Close")]
			function actions(index) {
				addUserDialog.rejected()
			}
			
			height: 160 + extraHeight
			width: Math.max(320, (1/2) * parent.width)
			
			property string addUserPageErrorMessage: ""
			
			ColumnLayout {
				anchors.margins:	sizes.regSpacing
				spacing:			sizes.regSpacing
				width: parent.width
				
				StyledLabel {
					anchors.horizontalCenter: parent.horizontalCenter
					text: qsTr("One-time invite code")
				}
				RowLayout {
					spacing: sizes.regSpacing
					
					StyledTextField {
						id: inviteCodeField
						readOnly: true
						text: root.code
						placeholderText: qsTr("Loading...")
						selectByMouse: true
						//implicitWidth: 72
						Layout.fillWidth: true
					}
					StyledButton {
						text: qsTr("Copy")
						onClicked: {
							inviteCodeField.selectAll()
							inviteCodeField.copy()
							inviteCodeField.deselect()
						}
					}
					StyledButton {
						accentButton: false
						text: qsTr("Generate new...")
						onClicked: generateInviteCode()
					}
				}
				StyledLabel {
					anchors.horizontalCenter: parent.horizontalCenter
					text: qsTr("Permanently add user")
				}
				RowLayout {
					spacing: sizes.regSpacing
					
					StyledTextField {
						id: addUserField
						readOnly: false
						placeholderText: qsTr("Username")
						Keys.onReturnPressed: addUser3Button.clicked()
						Layout.fillWidth: true
					}
					StyledButton {
						id: addUser3Button
						text: qsTr("Add")
						onClicked: {
							if (addUserField.text != "") {
								enabled = false
								addUserDialog.addUserPageErrorMessage = ""
								addUser(addUserField.text)
							}
						}
					}
				}
				StyledLabel {
					text: addUserDialog.addUserPageErrorMessage
					visible: text != ""
					color: colors.red
				
				}
				StyledLabel {
					text: qsTr("Adding User...")
					visible: !addUser3Button.enabled
					font.italic: true
				}
			}
		}
	}
	
	MessageDialog {
		id: savePromptDialog
		title: qsTr("MuseLab")
		text: qsTr("Save changes to") + " " + root.currentProjectName + " " + qsTr("before closing?") + "\n" +
			qsTr("Your changes are not yet backed up online.")
		modality: Qt.ApplicationModal
		icon: StandardIcon.Warning
		standardButtons: StandardButton.Save | StandardButton.Discard
		onAccepted: {
			saveScore(function () {finishLogOut()})
		}
		onDiscard: finishLogOut()
	}
	MessageDialog {
		id: connectionErrorDialog
		title:			qsTr("Connection Error")
		text:			qsTr("Unable to check for the latest plugin version.")
		detailedText:	(qsTr("Please make sure you are connected to the internet.") + "\n" +
						qsTr("If this error persists, contact the server host."))
		modality: Qt.ApplicationModal
		icon: StandardIcon.Warning
		standardButtons: StandardButton.Ok
		onAccepted: smartQuit()
	}
	MessageDialog {
		id: mu321Dialog
		title: qsTr("Unsupported MuseScore version")
		modality: Qt.ApplicationModal
		icon: StandardIcon.Warning
		standardButtons: StandardButton.Ok
		text: qsTr("Please update to MuseScore 3.6 to use MuseLab")
		detailedText: qsTr("For collaboration to work it is imperative that all users are running the same version of MuseScore.")
		onAccepted: smartQuit()
	}
	MessageDialog {
		id: mu4Dialog
		title: qsTr("Unsupported MuseScore version")
		modality: Qt.ApplicationModal
		icon: StandardIcon.Warning
		standardButtons: StandardButton.Ok
		text: qsTr("MuseLab is not yet compatible with MuseScore 4")
		detailedText: qsTr("MuseScore 4's Plugin API is missing some features essential for MuseLab to function." +  
			"Support is planned as soon as is possible.")
		onAccepted: smartQuit()
	}
	function smartQuit() {
		pluginWindow.visible = false
		if (mscoreMajorVersion < 4) Qt.quit()
		else quit()
	}
	
	ColorPalette {id: colors}
	FontSizePalette {id: fontSizes}
	SizePalette {id: sizes}
	
	Settings {
		id: settings
		category: "MuseLab"
		property var host
		property bool showToolTips: true
		property var x: pluginWindow.x
		property var y: pluginWindow.y
	}
}//MuseScore
