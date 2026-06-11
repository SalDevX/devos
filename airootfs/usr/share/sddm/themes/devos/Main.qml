// DevOS SDDM greeter — macOS Ventura minimalist, pure Qt6 (no Plasma, no Qt5Compat).
// Sharp wallpaper, no frosted card. Centered avatar + name + password pill.
// Top-right status cluster: battery · keyboard layout · clock. Bottom: icon-only
// power glyphs (sleep / restart / power). Theme API 2.0.
// Context objects from SDDM: sddm, userModel, sessionModel, screenModel,
// keyboard, config. All status icons are Canvas-drawn so they never depend on a
// font shipping a given Unicode glyph. Battery is read straight from sysfs
// (world-readable; the unprivileged `sddm` user can see it) since SDDM exposes
// no battery object to QML — it auto-hides on machines without a battery.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects

Rectangle {
    id: root
    color: "#0d0d0f"

    // ---- last-user details (name / realName / avatar) ----------------------
    property string lastUser: userModel.lastUser
    property string firstUser: ""
    property string realName: ""
    property url    avatarSource: ""
    function loginUser() { return lastUser && lastUser.length ? lastUser : firstUser }
    function displayName() { return realName && realName.length ? realName : loginUser() }

    // ---- background source resolution --------------------------------------
    property url bgFallback: "images/background.jpg"
    function resolveBg(p) {
        if (!p || !p.length) return bgFallback
        return (p.charAt(0) === "/") ? "file://" + p : p
    }

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

    // ---- battery (read from sysfs; SDDM exposes no battery object) ----------
    QtObject { id: bat; property int percent: -1; property bool charging: false }
    function xhrGet(path, cb) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                cb(((xhr.status === 200 || xhr.status === 0) && xhr.responseText.length)
                   ? xhr.responseText.replace(/\s+$/, "") : null)
        }
        try { xhr.open("GET", "file://" + path); xhr.send() } catch (e) { cb(null) }
    }
    property var batBases: ["/sys/class/power_supply/BAT0/",
                            "/sys/class/power_supply/BAT1/",
                            "/sys/class/power_supply/macsmc-battery/"]
    function batTry(i) {
        if (i >= batBases.length) { bat.percent = -1; return }
        xhrGet(batBases[i] + "capacity", function(cap) {
            if (cap === null) { batTry(i + 1); return }
            bat.percent = parseInt(cap)
            xhrGet(batBases[i] + "status", function(st) {
                bat.charging = st && (st.indexOf("Charging") >= 0 || st.indexOf("Full") >= 0)
            })
        })
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: root.batTry(0) }

    // ---- keyboard-layout helpers -------------------------------------------
    function kbLayout() {
        try {
            if (keyboard && keyboard.layouts && keyboard.layouts.length)
                return keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase()
        } catch (e) {}
        return ""
    }
    function cycleKb() {
        try {
            if (keyboard && keyboard.layouts && keyboard.layouts.length > 1)
                keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
        } catch (e) {}
    }

    // ===== Canvas-drawn icons (font-independent) ============================
    function roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r); ctx.closePath()
    }
    function drawGlyph(ctx, kind, w, h) {
        ctx.reset()
        ctx.strokeStyle = "white"; ctx.fillStyle = "white"
        ctx.lineWidth = Math.max(1.5, w * 0.075); ctx.lineCap = "round"; ctx.lineJoin = "round"
        var cx = w / 2, cy = h / 2, r = Math.min(w, h) * 0.34
        if (kind === "power") {
            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI * 0.30, Math.PI * 1.30, false); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(cx, cy - r * 1.05); ctx.lineTo(cx, cy - r * 0.05); ctx.stroke()
        } else if (kind === "restart") {
            var a0 = -Math.PI * 0.20, a1 = Math.PI * 1.15
            ctx.beginPath(); ctx.arc(cx, cy, r, a0, a1, false); ctx.stroke()
            var ex = cx + r * Math.cos(a0), ey = cy + r * Math.sin(a0)
            ctx.beginPath()
            ctx.moveTo(ex - r * 0.55, ey - r * 0.10); ctx.lineTo(ex, ey); ctx.lineTo(ex + r * 0.10, ey - r * 0.55)
            ctx.stroke()
        } else if (kind === "sleep") {
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath(); ctx.arc(cx + r * 0.55, cy - r * 0.35, r * 0.95, 0, 2 * Math.PI); ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        } else if (kind === "kbd") {
            var lw = ctx.lineWidth
            root.roundRect(ctx, lw, h * 0.24, w - 2 * lw, h * 0.52, h * 0.12); ctx.stroke()
            var kx = w * 0.27, ky = h * 0.40, gap = w * 0.155, ks = Math.max(1.2, w * 0.055)
            for (var rr = 0; rr < 2; rr++)
                for (var k = 0; k < 3; k++)
                    ctx.fillRect(kx + k * gap, ky + rr * h * 0.16, ks, ks)
        }
    }

    component GlyphButton: Item {
        property string kind
        property var action: (function() {})
        property bool interactive: true
        opacity: interactive ? (gma.containsMouse ? 1.0 : 0.72) : 0.92
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Canvas {
            anchors.fill: parent
            onPaint: root.drawGlyph(getContext("2d"), parent.kind, width, height)
            Component.onCompleted: requestPaint()
        }
        MouseArea {
            id: gma; anchors.fill: parent; enabled: parent.interactive
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.action()
        }
    }

    // ---- background : SHARP (no blur), with a faint dim for legibility ------
    Image {
        id: bg
        anchors.fill: parent
        source: root.resolveBg(config.background)
        onStatusChanged: if (status === Image.Error && source != root.bgFallback)
                             source = root.bgFallback
        fillMode: Image.PreserveAspectCrop
        smooth: true; cache: true
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.14 }

    // ---- TOP-RIGHT status cluster: battery · keyboard · clock ---------------
    Row {
        id: statusBar
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Math.round(root.height * 0.028)
        anchors.rightMargin: Math.round(root.height * 0.032)
        spacing: Math.round(root.height * 0.024)
        property real fs: Math.round(root.height * 0.020)
        property color fg: "#f2ffffff"

        // battery (hidden when no battery present — Row skips invisible items)
        Row {
            visible: bat.percent >= 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(statusBar.fs * 0.45)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: bat.percent + "%"; color: statusBar.fg
                style: Text.Outline; styleColor: "#55000000"
                font.family: "Geist"; font.pixelSize: statusBar.fs
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(statusBar.fs * 1.85); height: Math.round(statusBar.fs * 0.95)
                Rectangle {
                    id: batBody; anchors.fill: parent
                    radius: Math.round(width * 0.16); color: "transparent"
                    border.color: statusBar.fg; border.width: Math.max(1, Math.round(height * 0.11))
                }
                Rectangle {
                    anchors.left: batBody.right; anchors.leftMargin: Math.round(statusBar.fs * 0.06)
                    anchors.verticalCenter: batBody.verticalCenter
                    width: Math.round(statusBar.fs * 0.13); height: Math.round(parent.height * 0.42)
                    radius: 1; color: statusBar.fg
                }
                Rectangle {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Math.max(2, Math.round(parent.height * 0.20))
                    width: Math.max(0, (parent.width - 2 * Math.round(parent.height * 0.20)) * bat.percent / 100.0)
                    height: parent.height - 2 * Math.round(parent.height * 0.24)
                    radius: 1
                    color: bat.charging ? "#7CFC8A" : (bat.percent <= 15 ? "#ff6b6b" : statusBar.fg)
                }
            }
        }

        // keyboard layout (click the icon to cycle layouts)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(statusBar.fs * 0.4)
            visible: root.kbLayout().length > 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.kbLayout(); color: statusBar.fg
                style: Text.Outline; styleColor: "#55000000"
                font.family: "Geist"; font.pixelSize: statusBar.fs
            }
            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(statusBar.fs * 1.5); height: Math.round(statusBar.fs * 1.0)
                kind: "kbd"; action: function() { root.cycleKb() }
            }
        }

        // clock
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(clk.now, "H:mm"); color: statusBar.fg
            style: Text.Outline; styleColor: "#55000000"
            font.family: "Geist"; font.pixelSize: statusBar.fs
        }
    }

    // ---- centered login cluster (no card — floats on the wallpaper) ---------
    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Math.round(root.height * 0.03)
        spacing: Math.round(root.height * 0.018)
        property real shakeX: 0
        transform: Translate { x: col.shakeX }

        // avatar — circular, initial-letter fallback
        Rectangle {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(root.height * 0.125); height: width
            radius: width / 2
            color: "#26ffffff"
            border.color: "#80ffffff"; border.width: 1

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
            style: Text.Outline; styleColor: "#66000000"
            font.family: "Geist"; font.weight: Font.Medium
            font.pixelSize: Math.round(root.height * 0.026)
        }

        // translucent password pill
        Rectangle {
            id: pwPill
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(220, Math.min(300, Math.round(root.width * 0.17)))
            height: Math.round(root.height * 0.045)
            radius: height / 2
            color: "#33ffffff"
            border.width: 1
            border.color: pw.activeFocus ? "#99ffffff" : "#40ffffff"

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
            style: Text.Outline; styleColor: "#55000000"
            font.family: "Geist"; font.pixelSize: Math.round(root.height * 0.0175)
            text: keyboard.capsLock ? "Caps Lock is on" : ""
            opacity: text.length ? 1 : 0
        }
    }

    // ---- bottom: icon-only power glyphs (sleep · restart · power) -----------
    Row {
        id: powerRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.055)
        spacing: Math.round(root.width * 0.045)
        property real sz: Math.round(root.height * 0.032)
        GlyphButton { width: powerRow.sz; height: powerRow.sz; kind: "sleep"
                      action: function() { sddm.suspend() } }
        GlyphButton { width: powerRow.sz; height: powerRow.sz; kind: "restart"
                      action: function() { sddm.reboot() } }
        GlyphButton { width: powerRow.sz; height: powerRow.sz; kind: "power"
                      action: function() { sddm.powerOff() } }
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
        NumberAnimation { target: col; property: "shakeX"; to: 10;  duration: 45 }
        NumberAnimation { target: col; property: "shakeX"; to: -10; duration: 45 }
        NumberAnimation { target: col; property: "shakeX"; to: 6;   duration: 45 }
        NumberAnimation { target: col; property: "shakeX"; to: 0;   duration: 45 }
    }

    Component.onCompleted: { root.batTry(0); pw.forceActiveFocus() }
}
