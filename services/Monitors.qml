pragma Singleton
import QtQuick
import Quickshell

// The bar's MangoMonitor of each screen (bar/BarContent.qml puts it here),
// so the dock reads the same one instead of running a second
// `mmsg watch monitor <name>`.
Singleton {
    // { "<screen name>": MangoMonitor }
    property var byScreen: ({})

    function register(name, monitor) {
        const m = Object.assign({}, byScreen);
        if (monitor)
            m[name] = monitor;
        else
            delete m[name];
        byScreen = m;
    }
}
