import QtQuick
import Quickshell
import qs.common
import qs.services

// AI usage (services/AiUsage.qml): Claude's limits as two rings in one (the
// 5-hour window outside, the week inside) and Codex's window as one ring,
// orange past Style.aiUsageWarnAt, red past Style.aiUsageCriticalAt. Only
// the services you're signed in to; none: not on the bar. While it's on the
// bar, the numbers are checked every Style.aiUsagePoll minutes. Click: the
// popup with the details and reset times.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: AiUsage.any

    // Checking runs while this is on the bar.
    Component.onCompleted: AiUsage.use(true)
    Component.onDestruction: AiUsage.use(false)

    readonly property var claudeWins: AiUsage.windowsOf(AiUsage.claude)
    readonly property var codexWins: AiUsage.windowsOf(AiUsage.codex)
    readonly property var session: AiUsage.claude.data?.session ?? null
    readonly property var weekly: AiUsage.claude.data?.weekly ?? null
    // Codex: its tightest window.
    readonly property var codexTop: codexWins.length === 0 ? null
        : codexWins.reduce((a, b) => b.percent > a.percent ? b : a)

    function line(title, wins, s) {
        if (!s.present)
            return "";
        if (s.phase === "expired")
            return title + ": sign-in expired";
        if (wins.length === 0)
            return title + ": " + (s.error !== "" ? s.error : "checking…");
        return title + ": " + wins.slice(0, 3).map(w => w.label + " " + Math.round(w.percent) + "%").join(" · ");
    }

    Clickable {
        id: button
        spacing: 6
        tip: "AI usage"
        tipDetail: [root.line("Claude", root.claudeWins, AiUsage.claude), root.line("Codex", root.codexWins, AiUsage.codex)]
            .filter(t => t !== "").join("\n") + "\nClick: details and reset times"
        onClicked: {
            const win = button.QsWindow.window;
            BarPopupState.toggle("aiusage", win?.screen?.name ?? "",
                                 win ? win.itemRect(button) : Qt.rect(0, 0, 0, 0));
        }

        UsageRing {
            anchors.verticalCenter: parent.verticalCenter
            visible: AiUsage.claude.present
            size: 18
            value: (root.session?.percent ?? 0) / 100
            color: AiUsage.colorOf(root.session?.severity ?? "normal")
            inner: root.weekly ? root.weekly.percent / 100 : -1
            innerColor: AiUsage.colorOf(root.weekly?.severity ?? "normal")
            opacity: AiUsage.claude.phase === "ok" ? 1 : 0.45
        }
        UsageRing {
            anchors.verticalCenter: parent.verticalCenter
            visible: AiUsage.codex.present
            size: 18
            thickness: 3
            value: (root.codexTop?.percent ?? 0) / 100
            color: AiUsage.colorOf(root.codexTop?.severity ?? "normal")
            opacity: AiUsage.codex.phase === "ok" ? 1 : 0.45
        }
    }
}
