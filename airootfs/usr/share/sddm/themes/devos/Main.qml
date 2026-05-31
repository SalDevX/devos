// DevOS SDDM greeter — macOS-style, pure Qt6 (no Plasma, no Qt5Compat).
// Blurred wallpaper + frosted glass. Theme API 2.0.
// Context objects from SDDM: sddm, userModel, sessionModel, screenModel,
// keyboard, config.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects

Rectangle {
    id: root
    color: "#0d0d0f"

    // ---- last-user details (name / realName / avatar) ----------------------
    // userModel.lastUser can be empty on first boot, so fall back to the first
    // real user in the model.
    property string lastUser: userModel.lastUser
    property string firstUser: ""
    property string realName: ""
    property url    avatarSource: ""
    function loginUser() { return lastUser && lastUser.length ? lastUser : firstUser }
    function displayName() { return realName && realName.length ? realName : loginUser() }

    Repeater {
        model: userModel
        delegate: Item {
            Component.onCompleted: {
                if (index === 0 && !root.firstUser.length)
                    root.firstUser = model.name
                if (model.name === userModel.lastUser
                    || (!userModel.lastUser && index === 0)) {
                    root.realName = (model.realName && model.realName.length)
                                    ? model.realName : model.name
                    if (model.icon) root.avatarSource = model.icon
                }
            }
        }
    }

    // ---- live clock --------------------------------------------------------
    QtObject { id: clk; property var now: new Date() }
    Timer { interval: 1000; running: true; repeat: true
            onTriggered: clk.now = new Date() }

    // ---- background : crisp source (hidden) + Gaussian blur via MultiEffect -
    Image {
        id: bg
        anchors.fill: parent
        source: config.background ? config.background : "images/background.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: true; cache: true
        visible: false
        // overfill a touch so the blur never samples past the edges
        transform: Scale { origin.x: bg.width/2; origin.y: bg.height/2
                           xScale: 1.08; yScale: 1.08 }
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        blurMultiplier: 1.0
        brightness: -0.06
        saturation: 0.08
    }
    // dim for legibility
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.22 }

    // ---- top-center clock --------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.11)
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font.family: "Geist"; font.weight: Font.Light
            font.pixelSize: Math.round(root.height * 0.090)
            text: Qt.formatTime(clk.now, "HH:mm")
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"; opacity: 0.85
            font.family: "Geist"; font.weight: Font.Light
            font.pixelSize: Math.round(root.height * 0.022)
            text: Qt.formatDate(clk.now, "dddd, d MMMM")
        }
    }

    // ---- centered login cluster on a frosted-glass panel -------------------
    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round(root.height * 0.05)
        width: col.implicitWidth + Math.round(root.height * 0.10)
        height: col.implicitHeight + Math.round(root.height * 0.07)
        property real shakeX: 0
        transform: Translate { x: panel.shakeX }

        // frosted card (translucent over the already-blurred wallpaper)
        Rectangle {
            anchors.fill: parent
            radius: Math.round(root.height * 0.022)
            color: "#1cffffff"
            border.color: "#33ffffff"; border.width: 1
        }
        // subtle top highlight for the glass edge
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 1
            height: 1; radius: 1
            color: "#22ffffff"
        }

        Column {
            id: col
            anchors.centerIn: parent
            spacing: Math.round(root.height * 0.018)

            // avatar — circular, initial-letter fallback
            Rectangle {
                id: avatar
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(root.height * 0.125); height: width
                radius: width / 2
                color: "#26ffffff"
                border.color: "#66ffffff"; border.width: 1

                Text {
                    anchors.centerIn: parent
                    visible: root.avatarSource == ""
                    text: root.displayName().length ? root.displayName().charAt(0).toUpperCase() : "?"
                    color: "white"
                    font.family: "Geist"; font.weight: Font.Light
                    font.pixelSize: parent.width * 0.46
                }
                Image {
                    id: avatarImg
                    anchors.fill: parent
                    source: root.avatarSource
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                MultiEffect {
                    anchors.fill: avatarImg
                    source: avatarImg
                    visible: root.avatarSource != ""
                    maskEnabled: true
                    maskSource: ShaderEffectSource {
                        sourceItem: Rectangle {
                            width: avatar.width; height: avatar.height
                            radius: width / 2; color: "white"
                        }
                    }
                }
            }

            // real name
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.displayName()
                color: "white"
                font.family: "Geist"; font.weight: Font.Medium
                font.pixelSize: Math.round(root.height * 0.024)
            }

            // frosted password pill
            Rectangle {
                id: pwPill
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(240, Math.min(320, Math.round(root.width * 0.20)))
                height: Math.round(root.height * 0.046)
                radius: height / 2
                color: "#2effffff"
                border.width: 1
                border.color: pw.activeFocus ? "#99ffffff" : "#3dffffff"

                TextField {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: height + 4
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    placeholderText: "Enter Password"
                    placeholderTextColor: "#a6ffffff"
                    color: "white"
                    font.family: "Geist"
                    font.pixelSize: Math.round(root.height * 0.020)
                    verticalAlignment: TextInput.AlignVCenter
                    background: Item {}
                    focus: true
                    onAccepted: doLogin()
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - 10; height: width; radius: width / 2
                    color: "white"
                    visible: pw.text.length > 0
                    Text { anchors.centerIn: parent; text: "→"
                           color: "#0d0d0f"; font.pixelSize: parent.height * 0.62
                           font.family: "Geist" }
                    MouseArea { anchors.fill: parent; onClicked: doLogin() }
                }
            }

            // status line (caps-lock / login failure)
            Text {
                id: status
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#ffbdbd"
                font.family: "Geist"; font.pixelSize: Math.round(root.height * 0.0175)
                text: keyboard.capsLock ? "Caps Lock is on" : ""
                opacity: text.length ? 1 : 0
            }
        }
    }

    // ---- bottom action row (frosted text buttons) --------------------------
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.06)
        spacing: Math.round(root.width * 0.03)

        Repeater {
            model: [
                { label: "Sleep",     act: "suspend"  },
                { label: "Restart",   act: "reboot"   },
                { label: "Shut Down", act: "poweroff" }
            ]
            delegate: Text {
                text: modelData.label
                color: "white"
                opacity: ma.containsMouse ? 1.0 : 0.65
                font.family: "Geist"; font.pixelSize: Math.round(root.height * 0.0185)
                Behavior on opacity { NumberAnimation { duration: 120 } }
                MouseArea {
                    id: ma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.act === "suspend")  sddm.suspend()
                        else if (modelData.act === "reboot")   sddm.reboot()
                        else if (modelData.act === "poweroff") sddm.powerOff()
                    }
                }
            }
        }
    }

    // ---- behaviour ---------------------------------------------------------
    function doLogin() {
        status.text = ""
        sddm.login(root.loginUser(), pw.text, sessionModel.lastIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            status.color = "#ffbdbd"
            status.text = "Incorrect password"
            pw.selectAll(); pw.text = ""
            shake.restart()
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: panel; property: "shakeX"; to: 10;  duration: 45 }
        NumberAnimation { target: panel; property: "shakeX"; to: -10; duration: 45 }
        NumberAnimation { target: panel; property: "shakeX"; to: 6;   duration: 45 }
        NumberAnimation { target: panel; property: "shakeX"; to: 0;   duration: 45 }
    }

    Component.onCompleted: pw.forceActiveFocus()
}
