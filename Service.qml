// Service - supervises the tingd daemon (stdlib python, no venv) and exposes
// IPC target "ting" for hotkeys: omarchy-shell -q ting toggle|mute|panic|say

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    property bool daemonManaged: false

    // Probe: is tingd already answering? (An externally started daemon wins.)
    Process {
        id: probe
        command: ["python3", root.pluginDir + "/bin/tingctl", "status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.indexOf("\"ok\":true") !== -1) {
                    console.log("ting: externally managed tingd found; standing down")
                } else {
                    root.daemonManaged = true
                    daemon.running = true
                }
            }
        }
    }

    Process {
        id: daemon
        command: ["python3", root.pluginDir + "/bin/tingd"]
        stdout: SplitParser {
            onRead: function(line) { console.log("tingd:", line) }
        }
        stderr: SplitParser {
            onRead: function(line) { console.log("tingd:", line) }
        }
        onExited: {
            if (root.daemonManaged) restartDaemon.restart()
        }
    }

    Timer {
        id: restartDaemon
        interval: 3000
        onTriggered: {
            if (root.daemonManaged) daemon.running = true
        }
    }

    IpcHandler {
        target: "ting"

        function toggle() {
            root.ipcRun(["toggle"])
        }

        function mute() {
            root.ipcRun(["mute"])
        }

        function panic() {
            root.ipcRun(["panic"])
        }

        function say(text: string) {
            root.ipcRun(["say", text])
        }
    }

    function ipcRun(args) {
        ipcProc.command = ["python3", root.pluginDir + "/bin/tingctl"].concat(args)
        ipcProc.running = true
    }

    Process {
        id: ipcProc
        command: []
        stdout: SplitParser {
            onRead: function(line) { console.log("ting ipc:", line) }
        }
    }

    Component.onCompleted: probe.running = true
}
