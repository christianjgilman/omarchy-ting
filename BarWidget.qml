// Ting - pearl orb in the bar. Left-click: talk (barge-in while speaking).
// Right-click: the one settings menu for the whole Ting system.
// Settings panel pattern adapted from io.github.legibet.popup-translator (MIT).

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "champion.ting"

  property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string ctlCommand: decodeURIComponent(
    String(Qt.resolvedUrl("bin/tingctl")).replace(/^file:\/\//, ""))
  readonly property string watchCommand: decodeURIComponent(
    String(Qt.resolvedUrl("bin/ting-watch")).replace(/^file:\/\//, ""))

  // live state
  property string state: "idle"
  property bool muted: false
  property string brain: "mock"
  property string lastTranscript: ""
  property string lastReply: ""

  // settings form
  property string voice: "ting"
  property string providerName: "groq"
  property string providerBaseUrl: "https://api.groq.com/openai/v1"
  property string providerModel: "llama-3.1-8b-instant"
  property bool apiKeyConfigured: false
  property string apiKeyAction: "keep"
  property string updateCadence: "done"
  property bool loading: false
  property bool saving: false
  property bool saved: false
  property string errorText: ""
  property string loadStdout: ""
  property string saveStdout: ""
  property string pendingPayload: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool canSave: !loading && !saving
    && providerBaseUrl.trim() !== "" && providerModel.trim() !== ""

  readonly property color stateColor: {
    if (muted) return "#6b7280"
    if (state === "listening") return "#f5c2e7"
    if (state === "thinking" || state === "transcribing") return "#e0af68"
    if (state === "speaking") return "#7dcfff"
    return Color.accent
  }

  function restoreForm(cfg) {
    voice = cfg.voice === "tony" ? "tony" : "ting"
    updateCadence = cfg.update_cadence === "silent" ? "silent" : "done"
    var p = cfg.provider || {}
    providerName = p.name || "groq"
    providerBaseUrl = String(p.base_url || "https://api.groq.com/openai/v1")
    providerModel = String(p.model || "llama-3.1-8b-instant")
    apiKeyConfigured = p.api_key === "***set***"
    apiKeyAction = "keep"
    apiKeyField.text = ""
    voiceDropdown.value = voice
    cadenceDropdown.value = updateCadence
    providerDropdown.value = providerName
    baseUrlField.text = providerBaseUrl
    modelField.text = providerModel
  }

  function loadSettings() {
    if (loadProcess.running || saveProcess.running) return
    loading = true
    errorText = ""
    saved = false
    loadStdout = ""
    loadProcess.running = true
  }

  function finishLoad(exitCode) {
    loading = false
    if (exitCode !== 0) {
      errorText = "tingd is not answering."
      return
    }
    try {
      var result = JSON.parse(loadStdout)
      restoreForm(result.config || {})
    } catch (e) {
      errorText = "Config returned invalid data."
    }
  }

  function saveSettings() {
    if (!canSave) return
    var provider = {
      name: providerName,
      base_url: providerBaseUrl.trim(),
      model: providerModel.trim()
    }
    if (apiKeyAction === "set") provider.api_key = apiKeyField.text.trim()
    else if (apiKeyAction === "clear") provider.api_key = ""
    saving = true
    saved = false
    errorText = ""
    pendingPayload = JSON.stringify({
      voice: voice,
      update_cadence: updateCadence,
      provider: provider
    })
    saveProcess.running = true
  }

  function finishSave(exitCode) {
    saving = false
    var result = ({})
    try { result = JSON.parse(saveStdout) } catch (e) {}
    if (exitCode !== 0 || result.ok !== true) {
      errorText = "Unable to save settings."
      return
    }
    apiKeyConfigured = apiKeyAction === "set" ? true
      : (apiKeyAction === "clear" ? false : apiKeyConfigured)
    apiKeyField.text = ""
    apiKeyAction = "keep"
    saved = true
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  onOpenedChanged: {
    if (opened) {
      loadSettings()
      Qt.callLater(function() { panelFocus.forceActiveFocus() })
    }
  }

  // ---- live state watcher ----
  Process {
    id: watchProcess
    command: ["bash", root.watchCommand]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var parts = JSON.parse(line.trim())
          if (parts.length >= 5) {
            root.state = parts[0]
            root.muted = parts[1] === "1"
            root.lastTranscript = parts[2]
            root.lastReply = parts[3]
            root.brain = parts[4]
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: loadProcess
    running: false
    command: ["python3", root.ctlCommand, "get-config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadStdout = text
    }
    onExited: function(exitCode) { Qt.callLater(function() { root.finishLoad(exitCode) }) }
  }

  Process {
    id: saveProcess
    running: false
    command: ["python3", root.ctlCommand, "set-config",
              root.pendingPayload === "" ? "{}" : root.pendingPayload]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.saveStdout = text
    }
    onExited: function(exitCode) { Qt.callLater(function() { root.finishSave(exitCode) }) }
  }

  Process {
    id: ipcProc
    command: []
    stdout: SplitParser {
      onRead: function(line) { console.log("ting:", line) }
    }
  }

  function ctl(args) {
    ipcProc.command = ["python3", root.ctlCommand].concat(args)
    ipcProc.running = true
  }

  // ---- bar button + orb ----
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.opened
    tooltipText: "Ting · Left: talk · Right: settings"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.ctl(["toggle"])
      else if (buttonCode === Qt.RightButton)
        root.toggle()
    }

    Rectangle {
      id: orbRing
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) - Style.space(10)
      height: width
      radius: width / 2
      color: "transparent"
      border.color: root.stateColor
      border.width: root.muted ? 1 : 2

      Rectangle {
        id: pearl
        anchors.centerIn: parent
        width: parent.width - Style.space(5)
        height: width
        radius: width / 2
        color: root.stateColor

        // pearl shading: layered highlight circles (RadialGradient unavailable
        // in this shell's Qt build)
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.72
          height: width
          radius: width / 2
          color: Qt.lighter(root.stateColor, 1.6)
          opacity: 0.5
        }
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.4
          height: width
          radius: width / 2
          color: Qt.lighter(root.stateColor, 2.0)
          opacity: 0.7
        }

        Rectangle {
          // highlight
          anchors.top: parent.top
          anchors.topMargin: parent.height * 0.12
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width * 0.34
          height: width * 0.6
          radius: width / 2
          color: "#ffffff"
          opacity: 0.55
        }

        SequentialAnimation on scale {
          running: root.state === "listening"
          loops: Animation.Infinite
          NumberAnimation { to: 1.18; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.94; duration: 420; easing.type: Easing.InOutQuad }
        }

        SequentialAnimation on opacity {
          running: root.state === "speaking"
          loops: Animation.Infinite
          NumberAnimation { to: 0.65; duration: 260; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.InOutQuad }
        }
      }
    }
  }

  // ---- settings panel ----
  KeyboardPanel {
    id: settingsPanel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panelFocus
    contentWidth: settingsPanel.fittedContentWidth(Style.space(380))
    contentHeight: settingsPanel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(560))

    Item {
      id: panelFocus
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: settingsColumn
          width: parent.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: "Ting"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // STATUS
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "STATUS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: root.muted ? "Muted"
                : (root.state === "idle" ? "Listening for Alt+`" : root.state)
              color: root.stateColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              text: "Brain: " + root.brain + (root.brain === "mock"
                ? "  (set a provider key below)" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.lastTranscript !== ""
              width: parent.width
              text: "You: " + root.lastTranscript
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              visible: root.lastReply !== ""
              width: parent.width
              text: "Ting: " + root.lastReply
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              text: "Test voice"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              onClicked: root.ctl(["say", "Hi, I am Ting. All sessions are on track."])
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // VOICE
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "VOICE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: voiceDropdown
              width: parent.width
              label: "Voice"
              value: root.voice
              options: [
                { value: "ting", label: "Ting" },
                { value: "tony", label: "Tony" }
              ]
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading && !root.saving
              onChanged: function(value) {
                root.voice = value
                root.saved = false
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // BRAIN
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "BRAIN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: providerDropdown
              width: parent.width
              label: "Provider"
              value: root.providerName
              options: [
                { value: "groq", label: "Groq (fastest)" },
                { value: "omnirouter", label: "Omnirouter" },
                { value: "custom", label: "Custom OpenAI-compatible" }
              ]
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading && !root.saving
              onChanged: function(value) {
                root.providerName = value
                if (value === "groq") {
                  root.providerBaseUrl = "https://api.groq.com/openai/v1"
                  root.providerModel = "llama-3.1-8b-instant"
                  baseUrlField.text = root.providerBaseUrl
                  modelField.text = root.providerModel
                }
                root.saved = false
              }
            }

            Text {
              width: parent.width
              text: "Base URL"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: baseUrlField
              width: parent.width
              text: root.providerBaseUrl
              maximumLength: 2048
              placeholderText: "https://api.groq.com/openai/v1"
              foreground: root.foreground
              enabled: !root.loading && !root.saving
              onTextEdited: {
                root.providerBaseUrl = text
                root.saved = false
              }
            }

            Text {
              width: parent.width
              text: "Model"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: modelField
              width: parent.width
              text: root.providerModel
              maximumLength: 256
              placeholderText: "llama-3.1-8b-instant"
              foreground: root.foreground
              enabled: !root.loading && !root.saving
              onTextEdited: {
                root.providerModel = text
                root.saved = false
              }
            }

            Text {
              width: parent.width
              text: "API key"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: apiKeyField
              width: parent.width
              password: true
              maximumLength: 8192
              placeholderText: root.apiKeyConfigured ? "Replace stored API key" : "API key"
              foreground: root.foreground
              enabled: !root.loading && !root.saving
              onTextEdited: {
                root.apiKeyAction = text.trim() === "" ? "keep" : "set"
                root.saved = false
              }
            }

            Text {
              width: parent.width
              text: root.apiKeyAction === "set" ? "New key will be saved."
                : (root.apiKeyAction === "clear" ? "Key will be removed."
                  : (root.apiKeyConfigured ? "Key configured." : "No key: Ting runs her mock brain."))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // BEHAVIOR
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "BEHAVIOR"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: cadenceDropdown
              width: parent.width
              label: "Task updates"
              value: root.updateCadence
              options: [
                { value: "done", label: "Tell me when done" },
                { value: "silent", label: "Silent (notification only)" }
              ]
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading && !root.saving
              onChanged: function(value) {
                root.updateCadence = value
                root.saved = false
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item {
            width: parent.width
            height: saveButton.implicitHeight

            TextMetrics {
              id: savedLabelMetrics
              text: "Saved"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Button {
              id: saveButton
              anchors.right: parent.right
              width: Math.ceil(savedLabelMetrics.advanceWidth)
                + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
              text: root.saved ? "Saved" : "Save"
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.canSave && !root.saved
              onClicked: root.saveSettings()
            }
          }
        }
      }
    }
  }

  Component.onCompleted: watchProcess.running = true
}
