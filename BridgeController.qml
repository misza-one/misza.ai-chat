import QtQuick
import Quickshell.Io

QtObject {
  id: root

  required property string executable
  readonly property bool running: process.running

  signal line(string value)
  signal ready()
  signal failed(string message)

  function start() {
    if (!process.running) process.running = true
  }

  function send(payload) {
    if (!process.running) return false
    process.write(JSON.stringify(payload) + "\n")
    return true
  }

  property Process process: Process {
    id: process
    command: [root.executable]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function(value) { root.line(value) }
    }

    onStarted: root.ready()
    onExited: function(exitCode) {
      root.failed("AI bridge exited (code " + exitCode + ").")
    }
  }
}
