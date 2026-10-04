pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components

Item {
    id: root

    required property PopoutState popouts
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null

    // The tray items the bar actually shows. THIS FILTER MUST MATCH THE ONE IN
    // bar/components/Tray.qml EXACTLY: the "traymenu<N>" names index into this
    // same list, so any extra condition (e.g. hasMenu) shifts the indices and
    // makes right-click open the wrong item's menu - or none at all.
    readonly property var visibleTrayItems: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))

    readonly property var trayItemsToIndices: root.visibleTrayItems.reduce((acc, item, i) => {
        acc[item.id] = i;
        return acc;
    }, {})

    // The tray item whose menu should currently be shown (parsed from
    // popouts.currentName === "traymenu<N>").
    readonly property SystemTrayItem currentTrayItem: {
        const name = root.popouts.currentName;
        if (!name.startsWith("traymenu"))
            return null;
        const idx = parseInt(name.slice("traymenu".length));
        const items = root.visibleTrayItems;
        return idx >= 0 && idx < items.length ? items[idx] : null;
    }

    onCurrentTrayItemChanged: {
        // NOTE: currentTrayItem lives on this (Content) item, not on the
        // `trayMenu` Loader. Reading `trayMenu.currentTrayItem` yields
        // undefined, which made TrayMenu's trayItem binding always null and
        // therefore rendered a zero-sized - i.e. invisible - menu.
        if (trayMenu.shouldBeActive && root.currentTrayItem) {
            trayMenu.sourceComponent = null;
            trayMenu.sourceComponent = trayMenuComp;
        }
    }

    readonly property real contentMargin: Tokens.padding.large * (currentPopout?.item?.scaleOffset ?? 1.0)
    readonly property real availableWidth: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.width ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))
    readonly property real availableHeight: Math.max(0, ((QsWindow.window as QsWindow)?.screen?.height ?? 0) - contentMargin * 2 - Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0))

    implicitWidth: Math.min(((currentPopout?.item?.width || currentPopout?.implicitWidth) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableWidth)
    implicitHeight: Math.min(((currentPopout?.item?.height || currentPopout?.implicitHeight) ?? 0) + Tokens.padding.extraLargeIncreased * (currentPopout?.item?.scaleOffset ?? 1.0), availableHeight)

    Flickable {
        id: viewport

        anchors.fill: parent
        anchors.margins: root.contentMargin

        clip: true
        contentWidth: width
        contentHeight: Math.max(height, content.implicitHeight)

        Item {
            id: content

            width: viewport.width
            height: Math.max(viewport.height, implicitHeight)
            implicitHeight: currentPopout?.item?.implicitHeight ?? 0

        Popout {
            name: "greeter"
            previewKey: "greeter"
            sourceComponent: Greeter {
                popouts: root.popouts
            }
        }

        Popout {
            name: "greetercontext"
            previewKey: "greeter"
            sourceComponent: GreeterContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "activewindow"
            previewKey: "greeter"
            sourceComponent: Greeter {
                popouts: root.popouts
            }
        }

        Popout {
            id: networkPopout

            name: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: "wireless"
            }
        }

        Popout {
            name: "ethernet"
            previewKey: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: "ethernet"
            }
        }

        Popout {
            id: passwordPopout

            name: "wirelesspassword"
            previewKey: "network"
            sourceComponent: WirelessPassword {
                id: passwordComponent

                popouts: root.popouts
            }
        }

        Popout {
            name: "bluetooth"
            sourceComponent: Bluetooth {
                popouts: root.popouts
            }
        }

        Popout {
            name: "clock"
            sourceComponent: CalendarPopout {
                popouts: root.popouts
            }
        }

        Popout {
            name: "clockcontext"
            previewKey: "clock"
            sourceComponent: ClockContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "statusiconscontext"
            sourceComponent: StatusIconsContext {
                popouts: root.popouts
            }
        }

        Popout {
            name: "battery"
            sourceComponent: Battery {
                popouts: root.popouts
            }
        }

        Popout {
            name: "peripheralBattery"
            sourceComponent: PeripheralBattery {
            }
        }

        Popout {
            name: "github"
            sourceComponent: Github {
                popouts: root.popouts
            }
        }

        Popout {
            name: "updateIndicator"
            sourceComponent: Updates {
                popouts: root.popouts
            }
        }

        Popout {
            name: "audio"
            minScale: 0.9
            sourceComponent: Audio {
                popouts: root.popouts
            }
        }

        Popout {
            name: "nightlight"
            sourceComponent: NightLight {
                popouts: root.popouts
            }
        }

        Popout {
            name: "kblayout"
            sourceComponent: KbLayout {
                popouts: root.popouts
            }
        }

        Popout {
            name: "lockstatus"
            previewKey: "lockStatus"
            sourceComponent: LockStatus {
                popouts: root.popouts
            }
        }

        Popout {
            name: "notifications"
            sourceComponent: Notifications {
                popouts: root.popouts
            }
        }

        Popout {
            name: "dockhover"
            previewKey: "dock"
            sourceComponent: DockHover {
                popouts: root.popouts
            }
        }

        Popout {
            name: "dockcontext"
            previewKey: "dock"
            sourceComponent: DockContext {
                popouts: root.popouts
            }
        }

        // Single TrayMenu popout shared by all tray items: the popout's name
        // follows popouts.currentName (traymenu<N>) so the instance stays
        // mounted while switching between tray items. Only one TrayMenu ever
        // exists, which makes two menus rendering at once structurally
        // impossible (previously each item had its own Popout and a wedged
        // fade-out left the old menu visible under the new one).
        Popout {
            id: trayMenu

            name: "traymenu"
            matchPrefix: true
            previewKey: "trayMenu"
            sourceComponent: trayMenuComp

            Component {
                id: trayMenuComp

                TrayMenu {
                    popouts: root.popouts
                    // currentTrayItem is a property of Content (root), not of
                    // the trayMenu Loader - see onCurrentTrayItemChanged.
                    trayItem: root.currentTrayItem?.menu ?? null // qmllint disable unresolved-type
                }
            }
        }
    }
    }

    component Popout: Loader {
        id: popout

        required property string name
        property string previewKey: name
        // When true, shouldBeActive matches currentName starting with `name`
        // (used by the single shared tray popout: currentName is "traymenu<N>").
        property bool matchPrefix: false
        property real minScale: 0.1
        readonly property bool shouldBeActive: root.popouts.currentName === name || (matchPrefix && root.popouts.currentName.startsWith(name))

        readonly property real masterScale: !isNaN(GlobalConfig.bar.previewScale) ? GlobalConfig.bar.previewScale : 1.0
        readonly property real elementOffset: GlobalConfig.bar.perElementPreviewScale ? (!isNaN(GlobalConfig.bar.previewScales[previewKey]) ? GlobalConfig.bar.previewScales[previewKey] : 0.0) : 0.0
        readonly property real barScaleOffset: GlobalConfig.bar.previewScaleWithBar ? (!isNaN(GlobalConfig.bar.scale) ? GlobalConfig.bar.scale : 1.0) : 1.0
        readonly property real scaleOffset: Math.max(minScale, (masterScale + elementOffset) * barScaleOffset)
        readonly property real elementFontOffset: GlobalConfig.bar.perElementFontScale ? (!isNaN(GlobalConfig.bar.previewFontScales[previewKey]) ? GlobalConfig.bar.previewFontScales[previewKey] : 0.0) : 0.0
        readonly property real fontScale: Math.max(0.1, scaleOffset + (!isNaN(GlobalConfig.bar.fontScaleOffset) ? GlobalConfig.bar.fontScaleOffset : 0.0) + elementFontOffset)
        readonly property bool sidebarOpen: root.popouts.sidebarOpen && root.popouts.isHorizontal

        anchors.centerIn: parent

        opacity: 0
        active: false

        states: State {
            name: "active"
            when: popout.shouldBeActive

            PropertyChanges {
                popout.active: true
                popout.opacity: 1
            }
        }

        transitions: [
            Transition {
                from: "active"
                to: ""

                // Deactivate immediately (no fade-out): a fade-out leaves the old
                // popout semi-visible while the next one fades in, and an interrupted
                // transition can wedge it there for good (menus stacking on top of
                // each other).
                PropertyAction {
                    property: "opacity"
                }
                PropertyAction {
                    property: "active"
                }
            },
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        property: "opacity"
                        type: Anim.SlowEffects
                    }
                }
            }
        ]

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "scaleOffset"
            value: popout.scaleOffset
        }

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "fontScale"
            value: popout.fontScale
        }

        Binding {
            when: popout.item !== null
            target: popout.item
            property: "_isSidebarOpen"
            value: popout.sidebarOpen
        }
    }
}
