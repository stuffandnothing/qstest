import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Rectangle {
    id: root

    // --- Required plugin API properties ---
    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // --- Plugin state ---
    property var profiles: pluginApi?.pluginSettings?.profiles ?? ["Default", "Gaming", "Off"]
    property string activeProfile: pluginApi?.pluginSettings?.activeProfile ?? "Default"
    property string host: pluginApi?.pluginSettings?.serverHost ?? "127.0.0.1"
    property int port: pluginApi?.pluginSettings?.serverPort ?? 6742
    property bool rgbOn: activeProfile !== "Off"
    property bool expanded: false
    property bool busy: false

    // --- Sizing ---
    implicitWidth: expanded
        ? mainRow.implicitWidth + Style.marginM * 2
        : collapsedRow.implicitWidth + Style.marginM * 2
    implicitHeight: Style.barHeight
    color: Style.capsuleColor
    radius: Style.radiusM

    Behavior on implicitWidth {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    // --- Collapsed view ---
    RowLayout {
        id: collapsedRow
        anchors.centerIn: parent
        visible: !expanded
        spacing: Style.marginS

        NIcon {
            icon: root.rgbOn ? "lightbulb" : "lightbulb_off"
            color: root.rgbOn ? Color.mPrimary : Color.mOnSurfaceVariant
        }
        NText {
            text: root.activeProfile
            color: Color.mOnSurface
            pointSize: Style.fontSizeS
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = true
        }
    }

    // --- Expanded view ---
    RowLayout {
        id: mainRow
        anchors.centerIn: parent
        visible: expanded
        spacing: Style.marginXS

        // Clicking the icon collapses
        NIcon {
            icon: "lightbulb"
            color: Color.mPrimary

            MouseArea {
                anchors.fill: parent
                onClicked: root.expanded = false
            }
        }

        Repeater {
            model: root.profiles

            Rectangle {
                required property string modelData
                property bool isActive: root.activeProfile === modelData

                implicitWidth: profileLabel.implicitWidth + Style.marginS * 2
                implicitHeight: Style.barHeight - Style.marginXS * 2
                radius: Style.radiusS
                color: isActive ? Color.mPrimary : "transparent"
                opacity: root.busy ? 0.5 : 1.0

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                NText {
                    id: profileLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: isActive ? Color.mOnPrimary : Color.mOnSurface
                    pointSize: Style.fontSizeS
                    font.weight: isActive ? Font.Bold : Font.Normal
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.busy
                    onClicked: root.applyProfile(modelData)
                }
            }
        }
    }

    // --- Process ---
    Process {
        id: openrgbProc
        property string pendingProfile: ""

        stderr: StdioCollector {}

        stdout: StdioCollector {
            onStreamFinished: {
                var out = this.text
                Logger.i("OpenRGB", "stdout:", out)

                var success = out.indexOf("Profile loaded successfully") !== -1
                             || out.indexOf("Color set") !== -1
                             || out.indexOf("color set") !== -1

                root.busy = false

                if (success) {
                    root.activeProfile = openrgbProc.pendingProfile
                    if (root.pluginApi) {
                        root.pluginApi.pluginSettings.activeProfile = root.activeProfile
                        root.pluginApi.saveSettings()
                    }
                    root.expanded = false
                    ToastService.showNotice("RGB → " + root.activeProfile)
                    Logger.i("OpenRGB", "Profile applied:", root.activeProfile)
                } else {
                    ToastService.showError("OpenRGB: profile failed")
                    Logger.e("OpenRGB", "Unexpected output:", out)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            Logger.i("OpenRGB", "Process exited:", exitCode)
            // busy is cleared in onStreamFinished; failsafe in case stdout never fires
            root.busy = false
        }
    }

    // --- Functions ---
    function applyProfile(profileName) {
        if (root.busy) return
        root.busy = true
        openrgbProc.pendingProfile = profileName

        if (profileName === "Off") {
            openrgbProc.command = [
                "/usr/bin/openrgb",
                "--client", root.host + ":" + root.port,
                "--color", "000000"
            ]
        } else {
            openrgbProc.command = [
                "/usr/bin/openrgb",
                "--client", root.host + ":" + root.port,
                "-p", profileName
            ]
        }

        Logger.i("OpenRGB", "Running:", openrgbProc.command)
        openrgbProc.running = false
        openrgbProc.running = true
    }

    Component.onCompleted: {
        Logger.i("OpenRGB", "Widget loaded, active profile:", root.activeProfile)
    }
}