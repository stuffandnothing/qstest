import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Rectangle {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    property var profiles: pluginApi?.pluginSettings?.profiles ?? ["Default", "Gaming", "Off"]
    property string activeProfile: pluginApi?.pluginSettings?.activeProfile ?? "Default"
    property string host: pluginApi?.pluginSettings?.serverHost ?? "127.0.0.1"
    property int port: pluginApi?.pluginSettings?.serverPort ?? 6742
    property bool rgbOn: activeProfile !== "Off"
    property bool expanded: false
    property bool hovering: false
    property bool busy: false

    implicitWidth: {
        if (expanded) return mainRow.implicitWidth + Style.marginM * 2
        if (hovering) return hoverRow.implicitWidth + Style.marginM * 2
        return idleRow.implicitWidth + Style.marginM * 2
    }
    implicitHeight: Style.barHeight
    color: Style.capsuleColor
    radius: Style.radiusM

    Behavior on implicitWidth {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    // --- Hover delay timer ---
    Timer {
        id: hoverTimer
        interval: 300
        repeat: false
        onTriggered: root.hovering = true
    }

    // --- Collapse timer ---
    Timer {
        id: collapseTimer
        interval: 2000
        repeat: false
        onTriggered: root.expanded = false
    }

    // --- Right-click context menu ---
    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Settings", "action": "settings", "icon": "settings" }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)
            if (action === "settings") {
                if (pluginApi) BarService.openPluginSettings(root.screen, pluginApi.manifest)
            }
        }
    }

    // --- Idle: just the icon ---
    RowLayout {
        id: idleRow
        anchors.centerIn: parent
        visible: !expanded && !hovering
        spacing: Style.marginS

        NIcon {
            icon: root.rgbOn ? "lightbulb" : "lightbulb_off"
            color: root.rgbOn ? Color.mPrimary : Color.mOnSurfaceVariant
        }
    }

    // --- Hover: icon + active profile name ---
    RowLayout {
        id: hoverRow
        anchors.centerIn: parent
        visible: !expanded && hovering
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
    }

    // --- Expanded: icon + all profile buttons ---
    RowLayout {
        id: mainRow
        anchors.centerIn: parent
        visible: expanded
        spacing: Style.marginXS

        onVisibleChanged: if (visible) collapseTimer.restart()

        NIcon {
            icon: root.rgbOn ? "lightbulb" : "lightbulb_off"
            color: root.rgbOn ? Color.mPrimary : Color.mOnSurfaceVariant

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    collapseTimer.stop()
                    root.expanded = false
                }
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
                    onClicked: {
                        collapseTimer.restart()
                        root.applyProfile(modelData)
                    }
                }
            }
        }
    }

    // --- Outer mouse area: only active when NOT expanded ---
    // When expanded, clicks fall through to the profile button MouseAreas above
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        enabled: !root.expanded

        onEntered: hoverTimer.start()
        onExited: {
            hoverTimer.stop()
            root.hovering = false
        }

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                root.expanded = true
                collapseTimer.restart()
            } else if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen)
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
        root.busy = false

        // openrgb prints noise about failed i2c/hid connections regardless of success
        // actual failures would be caught by the process not running at all
        // so we treat any completion as success
        root.activeProfile = openrgbProc.pendingProfile
        if (root.pluginApi) {
            root.pluginApi.pluginSettings.activeProfile = root.activeProfile
            root.pluginApi.saveSettings()
        }
        root.expanded = false
        collapseTimer.stop()
        if (root.pluginApi?.pluginSettings?.notifications ?? true) {
    ToastService.showNotice("RGB → " + root.activeProfile)
}
        Logger.i("OpenRGB", "Profile applied:", root.activeProfile)
    }
}

        onExited: (exitCode, exitStatus) => {
            Logger.i("OpenRGB", "Process exited:", exitCode)
            root.busy = false
        }
    }

    function applyProfile(profileName) {
    if (root.busy) return
    root.busy = true
    openrgbProc.pendingProfile = profileName

    var offColor = (pluginApi?.pluginSettings?.offColor ?? "#000000").replace("#", "")
    var brightness = pluginApi?.pluginSettings?.brightness ?? 100
    var helper = Quickshell.env("HOME") + "/.config/noctalia/plugins/openrgb-control/openrgb-helper.py"

    if (profileName === "Off") {
        openrgbProc.command = [
            "python3", helper,
            "color", root.host, root.port.toString(), offColor
        ]
    } else {
        openrgbProc.command = [
            "python3", helper,
            "profile", root.host, root.port.toString(), profileName
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
