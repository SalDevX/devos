/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DevOS Calamares view module: devosnetwork — page UI
 *
 * "Connect before you install." Detects a wired link, lists Wi-Fi networks
 * (refreshed by the backend every few seconds), and connects via nmcli. Skip is
 * always available and never blocks. The backend object is exposed as `config`.
 *
 * Palette mirrors branding/devos/branding.desc exactly:
 *   background #1a1a1a · text #f0f0f0 · accent #1793d1
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"

    // DevOS palette + a few derived shades used only on this page.
    readonly property color cText:   "#f0f0f0"
    readonly property color cMuted:  "#9aa0a6"
    readonly property color cAccent: "#1793d1"
    readonly property color cSurface:"#242424"
    readonly property color cBorder: "#3a3a3a"
    readonly property color cGood:   "#3fb950"
    readonly property color cBad:    "#f85149"
    readonly property color cWarn:   "#d29922"

    // Selection state for the inline connect panel.
    property string selectedSsid: ""
    property bool   selectedSecured: false

    function selectNetwork(ssid, secured) {
        root.selectedSsid = ssid
        root.selectedSecured = secured
        pwField.text = ""
        pwField.forceActiveFocus()
    }

    // Wrong password / failure: clear the field so the user can retry cleanly.
    Connections {
        target: config
        function onStateChanged() {
            if (config.failed)
                pwField.text = ""
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 640)
        spacing: 18

        // ---- Header ---------------------------------------------------------
        Label {
            text: qsTr("Connect to a network")
            color: root.cText
            font.pixelSize: 26
            font.bold: true
            Layout.fillWidth: true
        }
        Label {
            text: qsTr("Get online before installing so DevOS can fetch updates and mirrors. "
                       + "Already on a wired connection? You're set — just continue.")
            color: root.cMuted
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Status banner --------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            visible: bannerText.text.length > 0
            color: root.cSurface
            border.width: 1
            border.color: config.online ? root.cGood
                          : config.failed ? root.cBad
                          : config.unavailable ? root.cWarn
                          : root.cBorder
            implicitHeight: bannerRow.implicitHeight + 24

            RowLayout {
                id: bannerRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                BusyIndicator {
                    running: config.connecting
                    visible: config.connecting
                    implicitWidth: 22; implicitHeight: 22
                }
                Rectangle {
                    visible: !config.connecting
                    width: 22; height: 22; radius: 11
                    color: config.online ? root.cGood
                           : config.failed ? root.cBad
                           : config.unavailable ? root.cWarn : root.cAccent
                    Label {
                        anchors.centerIn: parent
                        text: config.online ? "✓" : config.failed ? "✕" : "ℹ"
                        color: "#ffffff"; font.pixelSize: 14; font.bold: true
                    }
                }
                Label {
                    id: bannerText
                    Layout.fillWidth: true
                    text: config.online && config.ethernetConnected ? qsTr("Wired connection active — you're online.")
                          : config.statusMessage
                    color: root.cText
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---- Wi-Fi list (hidden once we're online) --------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 280
            visible: !config.online && !config.unavailable
            radius: 8
            color: root.cSurface
            border.width: 1
            border.color: root.cBorder
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 6
                model: config.networks
                spacing: 2
                ScrollBar.vertical: ScrollBar {}

                delegate: ItemDelegate {
                    id: netDelegate
                    width: list.width
                    height: 48
                    // Hoist signal strength so the bars Repeater (whose own
                    // modelData is its 0–3 index) can still read it.
                    property int netSignal: modelData.signal
                    highlighted: modelData.ssid === root.selectedSsid
                    onClicked: {
                        if (modelData.secured)
                            root.selectNetwork(modelData.ssid, true)
                        else {
                            root.selectNetwork(modelData.ssid, false)
                            config.connectToWifi(modelData.ssid, "")
                        }
                    }

                    background: Rectangle {
                        radius: 6
                        color: netDelegate.highlighted ? Qt.rgba(0.09, 0.58, 0.82, 0.18)
                               : netDelegate.hovered ? "#2c2c2c" : "transparent"
                    }

                    contentItem: RowLayout {
                        spacing: 12

                        Label {
                            Layout.fillWidth: true
                            text: modelData.ssid
                            color: root.cText
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }

                        // Security badge
                        Label {
                            text: modelData.security
                            color: modelData.secured ? root.cMuted : root.cGood
                            font.pixelSize: 12
                        }
                        // Lock glyph for secured networks
                        Label {
                            text: modelData.secured ? "🔒" : ""
                            font.pixelSize: 12
                        }

                        // Signal strength bars (0–4 from SIGNAL 0–100)
                        Row {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 4
                                    height: 6 + index * 4
                                    radius: 1
                                    anchors.bottom: parent.bottom
                                    property int bars: netDelegate.netSignal >= 80 ? 4
                                                       : netDelegate.netSignal >= 55 ? 3
                                                       : netDelegate.netSignal >= 30 ? 2
                                                       : netDelegate.netSignal > 0 ? 1 : 0
                                    color: index < bars ? root.cAccent : root.cBorder
                                }
                            }
                        }
                    }
                }

                // Empty / scanning hint
                Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: config.busy ? qsTr("Scanning for networks…") : qsTr("No Wi-Fi networks found.")
                    color: root.cMuted
                    font.pixelSize: 14
                }
            }
        }

        // ---- Inline connect panel (secured selection) -----------------------
        RowLayout {
            Layout.fillWidth: true
            visible: !config.online && root.selectedSsid.length > 0 && root.selectedSecured
            spacing: 10

            TextField {
                id: pwField
                Layout.fillWidth: true
                placeholderText: qsTr("Password for “%1”").arg(root.selectedSsid)
                echoMode: showPw.checked ? TextInput.Normal : TextInput.Password
                color: root.cText
                enabled: !config.connecting
                onAccepted: config.connectToWifi(root.selectedSsid, pwField.text)
                background: Rectangle {
                    radius: 6
                    color: "#1a1a1a"
                    border.width: 1
                    border.color: pwField.activeFocus ? root.cAccent : root.cBorder
                }
            }
            CheckBox {
                id: showPw
                text: qsTr("Show")
                contentItem: Label {
                    text: showPw.text; color: root.cMuted; font.pixelSize: 13
                    leftPadding: showPw.indicator.width + 4
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Button {
                text: qsTr("Connect")
                enabled: !config.connecting && pwField.text.length > 0
                onClicked: config.connectToWifi(root.selectedSsid, pwField.text)
            }
        }

        // ---- Action row -----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 10

            // Skip: ALWAYS present, ALWAYS enabled. Offline / wired installs must
            // never be blocked here. (Selecting Skip enables Calamares' Next.)
            Button {
                text: qsTr("Skip")
                enabled: true
                onClicked: config.skip()
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Rescan")
                enabled: !config.busy && !config.unavailable
                onClicked: config.refresh()
            }
        }
    }
}
