import QtQuick

// Holds back a new window's opening animation until the window has
// settled. Right after a window is made, its first frames are slow: the
// shell is still building what's in it (a list's cards, icons, pictures),
// and an animation that has already started jumps over those frames
// instead of moving. Until `settled`, a panel isn't showing yet (or sits
// exactly on its island), so the wait doesn't show; it's over after two
// quick frames in a row, or after 250 ms at most.
//   Settle { id: settle }   …   open: settle.settled && SomeState.open
Item {
    id: root

    property bool settled: false
    property int ticks: 0
    property int quick: 0

    FrameAnimation {
        running: !root.settled
        onTriggered: {
            // The first tick only says the window exists.
            if (++root.ticks === 1)
                return;
            root.quick = frameTime < 0.025 ? root.quick + 1 : 0;
            if (root.quick >= 2)
                root.settled = true;
        }
    }

    Timer {
        interval: 250
        running: !root.settled
        onTriggered: root.settled = true
    }
}
