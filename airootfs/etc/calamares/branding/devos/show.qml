import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide()
    }

    Timer {
        id: slideshowTimer
        interval: 5000
        repeat: true
        running: presentation.activatedInCalamares
        onTriggered: nextSlide()
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#1d2021"
        }
        Text {
            anchors.centerIn: parent
            text: "Welcome to DevOS"
            font.pixelSize: 32
            font.bold: true
            color: "#ebdbb2"
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 50 }
            text: "An Arch-based developer workstation — installing your system…"
            font.pixelSize: 16
            color: "#a89984"
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1d2021" }
        Text {
            anchors.centerIn: parent
            text: "Built for developers"
            font.pixelSize: 28; font.bold: true; color: "#ebdbb2"
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 50 }
            text: "XFCE desktop · LTS kernel · Brave · full dev toolchain"
            font.pixelSize: 16; color: "#a89984"
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1d2021" }
        Text {
            anchors.centerIn: parent
            text: "Apple MacBook ready"
            font.pixelSize: 28; font.bold: true; color: "#ebdbb2"
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 50 }
            text: "Broadcom WiFi · clamshell display switching · Magic Trackpad gestures"
            font.pixelSize: 16; color: "#a89984"
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1d2021" }
        Text {
            anchors.centerIn: parent
            text: "Almost there…"
            font.pixelSize: 28; font.bold: true; color: "#ebdbb2"
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 50 }
            text: "Setting up your environment. This will only take a few minutes."
            font.pixelSize: 16; color: "#a89984"
        }
    }
}
