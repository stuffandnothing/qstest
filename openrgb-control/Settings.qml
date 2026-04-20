import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null

    // --- Local state ---
    property string editHost: pluginApi?.pluginSettings?.serverHost
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.serverHost
        ?? "127.0.0.1"
    property int editPort: pluginApi?.pluginSettings?.serverPort
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.serverPort
        ?? 6742
    property color editOffColor: pluginApi?.pluginSettings?.offColor
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.offColor
        ?? "#000000"
    property string editDefaultProfile: pluginApi?.pluginSettings?.activeProfile
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.activeProfile
        ?? "Default"
    property int editBrightness: pluginApi?.pluginSettings?.brightness
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.brightness
        ?? 100
    property string newProfileName: ""
    property bool editNotifications: pluginApi?.pluginSettings?.notifications
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.notifications
        ?? true
    spacing: Style.marginM

    // --- ListModel for stable focus during editing ---
    ListModel {
        id: profilesModel
    }

    Component.onCompleted: {
        Logger.i("OpenRGB", "Settings UI loaded")
        var profiles = pluginApi?.pluginSettings?.profiles
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.profiles
            ?? ["Default", "Gaming", "Off"]
        for (var i = 0; i < profiles.length; i++) {
            profilesModel.append({ "name": profiles[i] })
        }
    }

    // --- Profiles ---
    NLabel {
        label: "Profiles"
        description: "Profile names must exactly match those saved in OpenRGB"
    }

    Repeater {
        model: profilesModel

        RowLayout {
            required property var model
            required property int index
            Layout.fillWidth: true
            spacing: Style.marginS

            NTextInput {
                Layout.fillWidth: true
                text: model.name
                onEditingFinished: profilesModel.set(index, { "name": text })
            }

            Rectangle {
                implicitWidth: Style.baseWidgetSize
                implicitHeight: Style.baseWidgetSize
                radius: Style.radiusS
                color: Color.mErrorContainer

                NIcon {
                    anchors.centerIn: parent
                    icon: "remove"
                    color: Color.mOnErrorContainer
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var removedName = profilesModel.get(index).name
                        profilesModel.remove(index)
                        if (root.editDefaultProfile === removedName)
                            root.editDefaultProfile = profilesModel.count > 0
                                ? profilesModel.get(0).name : ""
                    }
                }
            }
        }
    }

    // --- Add profile ---
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTextInput {
            Layout.fillWidth: true
            label: "Add Profile"
            placeholderText: "Profile name..."
            text: root.newProfileName
            onTextChanged: root.newProfileName = text
            onEditingFinished: {
                if (root.newProfileName.trim() !== "") {
                    profilesModel.append({ "name": root.newProfileName.trim() })
                    root.newProfileName = ""
                }
            }
        }

        Rectangle {
            implicitWidth: Style.baseWidgetSize
            implicitHeight: Style.baseWidgetSize
            radius: Style.radiusS
            color: root.newProfileName.trim() !== ""
                ? Color.mPrimaryContainer
                : Color.mSurfaceVariant

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            NIcon {
                anchors.centerIn: parent
                icon: "add"
                color: root.newProfileName.trim() !== ""
                    ? Color.mOnPrimaryContainer
                    : Color.mOnSurfaceVariant
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.newProfileName.trim() !== ""
                onClicked: {
                    profilesModel.append({ "name": root.newProfileName.trim() })
                    root.newProfileName = ""
                }
            }
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // --- Default profile ---
    NLabel {
        label: "Default Profile"
        description: "Active profile shown when the widget loads"
    }

    Repeater {
        model: profilesModel

        Rectangle {
            required property var model
            required property int index
            Layout.fillWidth: true
            implicitHeight: Style.baseWidgetSize
            radius: Style.radiusS
            color: root.editDefaultProfile === model.name
                ? Color.mPrimaryContainer
                : Color.mSurfaceVariant

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            NText {
                anchors.centerIn: parent
                text: model.name
                color: root.editDefaultProfile === model.name
                    ? Color.mOnPrimaryContainer
                    : Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                font.weight: root.editDefaultProfile === model.name
                    ? Font.Bold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.editDefaultProfile = model.name
            }
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // --- Brightness ---
    NLabel {
        label: "Brightness"
        description: "Applied when loading any profile: " + root.editBrightness + "%"
    }

    NSlider {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: root.editBrightness
        onValueChanged: root.editBrightness = value
    }
    NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
}

NToggle {
    Layout.fillWidth: true
    label: "Show Notifications"
    description: "Show a toast notification when a profile is applied"
    checked: root.editNotifications
    onToggled: (checked) => { root.editNotifications = checked }
}
    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // --- Off color ---
    NLabel {
        label: "Off Color"
        description: "Color sent to all devices when 'Off' is selected"
    }

    NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        selectedColor: root.editOffColor
        onColorSelected: (color) => {
            root.editOffColor = color
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // --- Server ---
    NTextInput {
        Layout.fillWidth: true
        label: "Server Host"
        description: "IP of the OpenRGB SDK server"
        placeholderText: "127.0.0.1"
        text: root.editHost
        onEditingFinished: root.editHost = text
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Server Port"
        description: "Port of the OpenRGB SDK server (default: 6742)"
        placeholderText: "6742"
        text: root.editPort.toString()
        onEditingFinished: {
            var p = parseInt(text)
            if (!isNaN(p)) root.editPort = p
        }
    }

    // --- Save ---
    function saveSettings() {
        if (!pluginApi) {
            Logger.e("OpenRGB", "Cannot save: pluginApi is null")
            return
        }
        var profiles = []
        for (var i = 0; i < profilesModel.count; i++) {
            profiles.push(profilesModel.get(i).name)
        }
        pluginApi.pluginSettings.profiles = profiles
        pluginApi.pluginSettings.activeProfile = root.editDefaultProfile
        pluginApi.pluginSettings.serverHost = root.editHost
        pluginApi.pluginSettings.serverPort = root.editPort
        pluginApi.pluginSettings.offColor = root.editOffColor.toString()
        pluginApi.pluginSettings.brightness = root.editBrightness
        pluginApi.pluginSettings.notifications = root.editNotifications
        pluginApi.saveSettings()
        Logger.i("OpenRGB", "Settings saved")
    }
}
