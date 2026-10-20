pragma Singleton
import QtQuick
import Quickshell

// Material 3 Expressive motion tokens (https://m3.material.io/styles/motion/overview/specs).
// Same curves as the lock screen, so the bar moves the same way.
Singleton {
    // Spatial curves overshoot a little, so things settle like a spring.
    readonly property var fastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property var defaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
    readonly property var slowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
    // Effect curves (opacity, color, blur) never overshoot.
    readonly property var fastEffects: [0.31, 0.94, 0.34, 1.00, 1, 1]
    readonly property var defaultEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
    readonly property var emphasizedDecel: [0.05, 0.70, 0.10, 1.00, 1, 1]
    // For big shapes (islands growing into cards, panels resizing): smooth,
    // no bounce. Same values as end-4 (modules/common/Appearance.qml).
    readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
    readonly property var emphasizedAccel: [0.30, 0, 0.80, 0.15, 1, 1]
    // Small things sliding out of the bar on hover (Reveal, the window
    // title): eases in and out evenly. `emphasized` there did most of the
    // way in the first frames, then crept for a quarter of a second.
    readonly property var gentle: [0.30, 0, 0.20, 1, 1, 1]

    readonly property int fast: 350
    readonly property int normal: 500
    readonly property int slow: 650

    readonly property int morphIn: 500     // island → card
    readonly property int morphOut: 420    // card → back into the island
    readonly property int resize: 380      // a card changing height while open
    readonly property int reveal: 340      // something sliding out of the bar (Reveal)
    readonly property int contentIn: 320   // content arriving
    readonly property int contentOut: 110  // content leaving
}
