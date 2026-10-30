import QtQuick
import qs.common
import qs.services

// The AI usage popup's content (in BarPopupCard, a click on the bar's "AI
// usage"): per service you're signed in to, its rings and each limit with
// when it resets.
//
//      Claude                                     Max
//      (◯ 2%)  (◯ 29%)
//      5-hour  Weekly
//      5-hour                    2%   resets in 1 h 32 m
//      Weekly                   29%   resets Wed 13:59
//      Fable (weekly)            0%   resets Wed 14:00
//      Last 7 days   Claude Code 99% · Chats 1%
//      Updated 3 min ago
//      ─────
//      Codex                                     Free
//      …
//      Refresh                   Usage settings…
//
// Everything comes from services/AiUsage.qml (checked while this is open).
Column {
    id: root

    Component.onCompleted: {
        AiUsage.use(true);
        AiUsage.refreshIfOld();
    }
    Component.onDestruction: AiUsage.use(false)

    // The "resets in" and "updated … ago" texts move on while it's open.
    property real now: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    StyledText {
        x: 6
        width: parent.width - 12
        visible: !AiUsage.any
        topPadding: 6
        bottomPadding: 6
        text: "Not signed in to Claude Code or Codex"
        color: Colors.textOnSurfaceVariant
        wrapMode: Text.Wrap
    }

    ServiceBlock {
        source: AiUsage.claude
        visible: AiUsage.claude.present
    }
    Rule {
        visible: AiUsage.claude.present && AiUsage.codex.present
    }
    ServiceBlock {
        source: AiUsage.codex
        visible: AiUsage.codex.present
    }

    Rule {}
    Item {
        width: parent.width
        height: 28

        ActionRow {
            width: parent.width / 2 - 2
            text: AiUsage.claude.busy || AiUsage.codex.busy ? "Checking…" : "Refresh"
            onClicked: AiUsage.refresh()
        }
        ActionRow {
            x: parent.width / 2 + 2
            width: parent.width / 2 - 2
            text: "Usage settings…"
            onClicked: {
                BarPopupState.close();
                SettingsState.show("usage");
            }
        }
    }

    // One service: name and plan, rings, the limits, the 7-day breakdown
    // (Claude), when it was checked or why it couldn't be.
    component ServiceBlock: Column {
        id: block
        property AiUsageSource source
        readonly property var wins: AiUsage.windowsOf(source)
        readonly property var breakdown: source?.service === "claude" ? (source?.data?.breakdown ?? []).filter(r => r.percent > 0) : []
        width: root.width

        Item {
            width: parent.width
            height: 26

            StyledText {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: block.source?.title ?? ""
                role: "title"
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: block.source?.plan ?? ""
                color: Colors.textOnSurfaceVariant
            }
        }

        // The big rings: the first two windows (Claude: 5-hour and weekly).
        Row {
            x: 6
            topPadding: 6
            bottomPadding: 4
            spacing: 18
            visible: block.wins.length > 0

            Repeater {
                model: block.wins.slice(0, 2)

                Column {
                    required property var modelData
                    spacing: 4

                    Item {
                        width: 56
                        height: 56

                        UsageRing {
                            anchors.fill: parent
                            size: 56
                            thickness: 6
                            gap: 0
                            value: modelData.percent / 100
                            color: AiUsage.colorOf(modelData.severity)
                            opacity: block.source?.phase === "ok" ? 1 : 0.45
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: Math.round(modelData.percent) + "%"
                            role: "label"
                            weight: 650
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }
        }

        // Every limit, with its reset time.
        Repeater {
            model: block.wins

            Item {
                required property var modelData
                required property int index
                width: block.width
                height: 24

                StyledText {
                    id: limitName
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 104
                    text: block.source?.service === "claude" && index >= 2 ? modelData.label + " (weekly)" : modelData.label
                    elide: Text.ElideRight
                    color: Colors.textOnSurfaceVariant
                }
                StyledText {
                    id: limitPercent
                    x: 114
                    width: 40
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(modelData.percent) + "%"
                    font.features: ({ "tnum": 1 })
                    weight: modelData.severity === "normal" ? Style.textWeight("body") : 650
                    color: modelData.severity === "normal" ? Colors.textOnSurface : AiUsage.colorOf(modelData.severity)
                }
                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 166 - 6
                    horizontalAlignment: Text.AlignRight
                    text: root.now > 0 ? AiUsage.resetText(modelData.resetsAt) : ""
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        // Claude: where the week's use went.
        Item {
            width: block.width
            height: 24
            visible: block.breakdown.length > 0

            StyledText {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Last 7 days"
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 110
                horizontalAlignment: Text.AlignRight
                text: block.breakdown.map(r => r.label + " " + Math.round(r.percent) + "%").join(" · ")
                role: "caption"
                elide: Text.ElideRight
            }
        }

        StyledText {
            x: 6
            width: block.width - 12
            topPadding: 2
            bottomPadding: 4
            text: {
                const s = block.source;
                if (!s)
                    return "";
                if (s.phase === "expired")
                    return s.error;
                const when = s.fetchedAt > 0 && root.now > 0 ? "Updated " + AiUsage.agoText(s.fetchedAt) : s.busy ? "Checking…" : "";
                return [s.error, when].filter(t => t !== "").join(" · ");
            }
            role: "caption"
            color: block.source?.phase === "expired" ? Colors.error : Colors.textOnSurfaceVariant
            wrapMode: Text.Wrap
        }
    }

    // A row you click, like "Battery settings…".
    component ActionRow: MouseArea {
        id: action
        property string text: ""
        width: root.width
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Colors.textOnSurface
            opacity: action.pressed ? Style.pressTint : action.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        StyledText {
            anchors.centerIn: parent
            text: action.text
        }
    }

    // A thin line between the parts, like macOS menus.
    component Rule: Item {
        width: root.width
        height: 13

        Rectangle {
            x: 6
            width: parent.width - 12
            height: 1
            anchors.verticalCenter: parent.verticalCenter
            color: Style.alpha(Colors.textOnSurface, 0.1)
        }
    }
}
