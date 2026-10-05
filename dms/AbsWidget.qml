import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Model.js" as Model

// DankMaterialShell bar widget for the Audiobookshelf plugin. DMS creates one
// of these per bar, so it holds no state of its own: the player, poller, IPC
// handler and library live once in the daemon (AbsDaemon.qml), and this file
// only draws them. DMS also rebuilds popoutContent each time the popout opens.
PluginComponent {
  id: root

  layerNamespacePlugin: "abs-player"
  popoutWidth: Math.round(Theme.fontSizeMedium * 40)

  // The plugin's single daemon instance; null for a moment while DMS spawns it.
  readonly property var core: pluginService ? (pluginService.pluginDaemonInstances[pluginId] || null) : null
  readonly property var player: core ? core.player : null
  readonly property bool newEpisodes: core !== null && core.poller.unreadCount > 0

  // Sizes the popout uses, derived from Theme tokens.
  readonly property real coverLarge: Theme.iconSizeLarge * 7
  readonly property real coverSmall: Theme.iconSizeLarge + Theme.spacingXL
  readonly property real rowCover: Theme.iconSizeLarge + Theme.spacingL
  readonly property real rowMinHeight: Theme.iconSize + Theme.spacingL + Theme.spacingXS
  readonly property real listHeight: Math.round(Theme.fontSizeMedium * 51)
  readonly property real chipHeight: Theme.iconSize + Theme.spacingM
  readonly property real smallButtonHeight: Theme.iconSize + Theme.spacingS
  readonly property real logoSize: Theme.iconSizeLarge * 4

  pillRightClickAction: () => { if (root.player) root.player.togglePause() }

  // Register with the daemon so its toggle IPC call can find this bar.
  property var registeredWith: null
  function attach() {
    if (registeredWith === core) return
    if (registeredWith) registeredWith.unregisterView(root)
    registeredWith = core
    if (core) core.registerView(root)
  }
  onCoreChanged: attach()
  Component.onCompleted: attach()
  Component.onDestruction: if (registeredWith) registeredWith.unregisterView(root)

  // ---- Bar pill --------------------------------------------------------------
  // New episodes tint the icon with the theme's primary color.
  horizontalBarPill: Component {
    DankIcon {
      name: "headphones"
      size: root.iconSize
      color: root.newEpisodes ? Theme.primary : Theme.widgetIconColor
      opacity: root.player && root.player.playing ? 1 : 0.85
    }
  }

  verticalBarPill: Component {
    DankIcon {
      name: "headphones"
      size: root.iconSize
      color: root.newEpisodes ? Theme.primary : Theme.widgetIconColor
    }
  }

  // ---- Popout ----------------------------------------------------------------
  popoutContent: Component {
    PopoutComponent {
      id: pop

      Component.onCompleted: root.core.poller.unreadCount = 0

      Item {
        id: bodyHost
        width: parent.width
        // DMS's popout container takes focus when it opens and only handles
        // Esc (close). This item takes focus right after it and handles the
        // plugin's keys; anything it doesn't accept (Esc with nothing to go
        // back from) bubbles up to the container. Keys the text fields don't
        // use bubble up here too.
        focus: true
        Timer { interval: 50; running: true; onTriggered: bodyHost.forceActiveFocus() }
        // DMS's container can take focus back after the timer above (it grabs
        // focus again once the popout becomes visible), and Tab can move focus
        // onto a button. Whenever focus lands anywhere but here or a text
        // field, take it back so keys keep working.
        readonly property Item focusNow: Window.activeFocusItem
        onFocusNowChanged: if (focusNow !== bodyHost && !anyFieldFocused()) refocus.restart()
        Timer { id: refocus; interval: 30; onTriggered: if (!bodyHost.anyFieldFocused()) bodyHost.forceActiveFocus() }

        function anyFieldFocused() {
          return searchField.getActiveFocus() || urlField.getActiveFocus()
            || userField.getActiveFocus() || passField.getActiveFocus()
        }
        function moved(ok) { if (ok) itemList.positionViewAtIndex(root.core.cursor, ListView.Contain) }

        Keys.onPressed: function(event) {
          var k = event.key
          var t = event.text
          if (anyFieldFocused()) {
            // Leave a field: Esc anywhere, Down from search into the list.
            if (k === Qt.Key_Escape || (k === Qt.Key_Down && searchField.getActiveFocus())) {
              bodyHost.forceActiveFocus()
              if (k === Qt.Key_Down) moved(root.core.moveCursor(0))
              event.accepted = true
            }
            return
          }
          event.accepted = true
          if (k === Qt.Key_Escape) event.accepted = root.core.goBack()
          else if (k === Qt.Key_Down || t === "j") moved(root.core.moveCursor(1))
          else if (k === Qt.Key_Up || t === "k") moved(root.core.moveCursor(-1))
          else if (k === Qt.Key_Home) moved(root.core.jumpTo(true))
          else if (k === Qt.Key_End) moved(root.core.jumpTo(false))
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!root.core.activateSelected()) root.player.togglePause() }
          else if (k === Qt.Key_Space) root.player.togglePause()
          else if (k === Qt.Key_Left || t === "h") root.player.skip(-30)
          else if (k === Qt.Key_Right || t === "l") root.player.skip(30)
          else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.core.cycleType()
          else if (t === "/" || t === "a") { if (root.core.configured && !root.core.settingsView && root.core.openPodcast === null) searchField.forceActiveFocus() }
          else if (t === "q" || t === "R") root.core.refresh()
          else if (t === "r" || t === "f") root.core.toggleFinishedSelected()
          else if (t === "n") root.core.skipChapter(1)
          else if (t === "p") root.core.skipChapter(-1)
          else if (t === "[") root.core.setSpeed(Number(Model.stepSpeed(root.core.speed, -1)))
          else if (t === "]") root.core.setSpeed(Number(Model.stepSpeed(root.core.speed, 1)))
          else if (t === "c") { if (root.player.chapters.length > 0) root.core.chaptersOpen = !root.core.chaptersOpen }
          else if (t === "1") { if (root.core.configured) root.core.goHome() }
          else if (t === "2") { if (root.core.hasBooks) root.core.browseType("book") }
          else if (t === "3") { if (root.core.hasPodcasts) root.core.browseType("podcast") }
          else if (t === ",") { if (root.core.configured) root.core.settingsView = !root.core.settingsView }
          else event.accepted = false
        }

        // Home and settings size to their content; lists get a fixed height.
        readonly property bool compact: root.core.onHome || root.core.settingsView
        implicitHeight: compact ? body.implicitHeight + Theme.spacingM : root.listHeight

        ColumnLayout {
          id: body
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: bodyHost.compact ? implicitHeight : bodyHost.height
          spacing: Theme.spacingM

          // Header
          RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankActionButton {
              visible: !root.core.onHome
              iconName: "arrow_back"
              tooltipText: "Back (Esc)"
              onClicked: root.core.goBack()
            }

            StyledText {
              Layout.fillWidth: true
              text: root.core.settingsView ? (root.core.configured ? "Settings" : "Connect to Audiobookshelf")
                : root.core.openPodcast ? root.core.openPodcast.media.metadata.title
                : root.core.browsing ? (root.core.filterType === "podcast" ? "Podcasts" : root.core.filterType === "book" ? "Books" : "Search")
                : ""
              font.pixelSize: Theme.fontSizeLarge
              font.weight: Font.Bold
              color: Theme.surfaceText
              elide: Text.ElideRight
            }

            DankActionButton {
              visible: root.core.configured
              iconName: "home"
              tooltipText: "Library home (1)"
              onClicked: root.core.goHome()
            }
            DankActionButton {
              id: refreshButton
              visible: root.core.configured && !root.core.settingsView
              iconName: "refresh"
              tooltipText: "Refresh library (q / R)"
              onClicked: root.core.refresh()
              // The button is circular, so spinning the whole thing reads as
              // a spinning icon.
              RotationAnimation on rotation {
                running: root.core.refreshing
                from: 0; to: 360
                duration: 900
                loops: Animation.Infinite
                onRunningChanged: if (!running) refreshButton.rotation = 0
              }
            }
            DankActionButton {
              visible: root.core.configured
              iconName: "settings"
              tooltipText: "Settings (,)"
              onClicked: root.core.settingsView = !root.core.settingsView
            }
            DankActionButton {
              iconName: "close"
              tooltipText: "Close (Esc)"
              onClicked: pop.closePopout && pop.closePopout()
            }
          }

          // ---- Connection form ---------------------------------------------
          ColumnLayout {
            visible: root.core.settingsView
            Layout.fillWidth: true
            spacing: Theme.spacingS

            StyledText {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              text: "Your password goes straight to the server to get a login token, which is stored in the system keyring. It's never saved to a file."
              color: Theme.surfaceVariantText
              font.pixelSize: Theme.fontSizeSmall
            }
            DankTextField { id: urlField; Layout.fillWidth: true; placeholderText: "Server URL, e.g. http://localhost:13378"; text: root.core.serverUrl }
            DankTextField { id: userField; Layout.fillWidth: true; placeholderText: "Username" }
            DankTextField { id: passField; Layout.fillWidth: true; placeholderText: "Password"; echoMode: TextInput.Password; showPasswordToggle: true }
            Connections { target: root.core; function onLoginSucceeded() { passField.text = "" } }

            StyledText {
              Layout.fillWidth: true
              visible: root.core.setupError !== ""
              text: root.core.setupError
              wrapMode: Text.WordWrap
              color: Theme.error
              font.pixelSize: Theme.fontSizeSmall
            }

            DankButton {
              text: root.core.setupBusy ? "Connecting..." : "Connect"
              iconName: "login"
              onClicked: root.core.login(urlField.text.trim(), userField.text.trim(), passField.text)
            }

            // Library pickers only when there's a choice to make.
            Repeater {
              model: ["book", "podcast"]
              delegate: ColumnLayout {
                required property string modelData
                readonly property var libs: root.core.librariesOfType(modelData)
                visible: root.core.configured && libs.length > 1
                Layout.fillWidth: true
                StyledText {
                  text: modelData === "book" ? "Books library" : "Podcasts library"
                  color: Theme.surfaceVariantText
                  font.pixelSize: Theme.fontSizeSmall
                }
                DankButtonGroup {
                  model: libs.map(function(l) { return l.name })
                  currentIndex: libs.findIndex(function(l) { return l.id === (modelData === "book" ? root.core.bookLibId : root.core.podcastLibId) })
                  onSelectionChanged: function(index, selected) { if (selected) root.core.chooseLibrary(modelData, libs[index].id) }
                }
              }
            }

            StyledText {
              visible: root.core.configured
              Layout.fillWidth: true
              Layout.topMargin: Theme.spacingM
              wrapMode: Text.WordWrap
              text: "Disconnect removes this server's login and settings from this computer. Your Audiobookshelf account and progress stay on the server."
              color: Theme.surfaceVariantText
              font.pixelSize: Theme.fontSizeSmall
            }
            DankButton {
              visible: root.core.configured
              text: root.core.confirmDisconnect ? "Click again to disconnect" : "Disconnect"
              iconName: "logout"
              backgroundColor: root.core.confirmDisconnect ? Theme.error : Theme.surfaceContainerHigh
              textColor: root.core.confirmDisconnect ? Theme.primaryText : Theme.surfaceText
              onClicked: root.core.disconnectClicked()
            }

            // Keyboard reference, same keys as the Omarchy plugin.
            StyledText {
              Layout.fillWidth: true
              Layout.topMargin: Theme.spacingM
              text: "Keyboard"
              font.pixelSize: Theme.fontSizeMedium
              font.weight: Font.Bold
              color: Theme.surfaceText
            }
            TextMetrics { id: keyChipProbe; text: "Right-click"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold }
            GridLayout {
              Layout.fillWidth: true
              columns: 4
              columnSpacing: Theme.spacingM
              rowSpacing: Theme.spacingXS
              Repeater {
                model: root.core.keyHelp
                delegate: Item {
                  required property var modelData
                  // Each entry spans two cells: a key chip, then its action.
                  Layout.columnSpan: 2
                  Layout.fillWidth: true
                  implicitHeight: Math.max(keyChip.height, actionText.implicitHeight)
                  Rectangle {
                    id: keyChip
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: keyChipProbe.advanceWidth + Theme.spacingM * 2
                    height: keyText.implicitHeight + Theme.spacingXS * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    StyledText {
                      id: keyText
                      anchors.centerIn: parent
                      text: modelData.key
                      font.pixelSize: Theme.fontSizeSmall
                      font.weight: Font.Bold
                      color: Theme.primary
                    }
                  }
                  StyledText {
                    id: actionText
                    anchors.left: keyChip.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.action
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                  }
                }
              }
            }
          }

          // ---- Home: big player, or the logo when nothing is loaded ---------
          NowPlaying {
            Layout.fillWidth: true
            large: true
            visible: root.core.onHome && (root.player.hasItem || root.player.errorText !== "")
          }

          Column {
            visible: root.core.onHome && !root.player.hasItem && root.player.errorText === ""
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingL
            spacing: Theme.spacingS
            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              source: root.core.serverUrl !== "" ? root.core.serverUrl + "/icon.svg" : ""
              sourceSize.width: root.logoSize
              sourceSize.height: root.logoSize
              width: root.logoSize
              height: root.logoSize
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
            StyledText {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Audiobookshelf"
              font.pixelSize: Theme.fontSizeXLarge
              font.weight: Font.Bold
              color: Theme.surfaceText
            }
            StyledText {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.core.serverUrl !== ""
              text: root.core.serverUrl
              font.pixelSize: Theme.fontSizeSmall
              color: urlMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
              MouseArea {
                id: urlMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(root.core.serverUrl)
              }
            }
          }

          // ---- Compact player while browsing -------------------------------
          NowPlaying {
            Layout.fillWidth: true
            large: false
            visible: !root.core.settingsView && !root.core.onHome && (root.player.hasItem || root.player.errorText !== "")
          }

          // ---- Search + type buttons ---------------------------------------
          RowLayout {
            visible: root.core.configured && !root.core.settingsView && root.core.openPodcast === null
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankTextField {
              id: searchField
              Layout.fillWidth: true
              placeholderText: "Search title or author  (/ or a)"
              leftIconName: "search"
              showClearButton: true
              text: root.core.filterText
              onTextEdited: root.core.setSearch(text)
            }

            Repeater {
              model: root.core.typeOptions
              delegate: DankButton {
                required property string modelData
                text: modelData === "book" ? "Books" : "Podcasts"
                iconName: modelData === "book" ? "book_2" : "podcasts"
                buttonHeight: root.chipHeight
                backgroundColor: root.core.browsing && root.core.filterType === modelData ? Theme.primary : Theme.surfaceContainerHigh
                textColor: root.core.browsing && root.core.filterType === modelData ? Theme.primaryText : Theme.surfaceText
                onClicked: root.core.browseType(modelData)
                HoverTip { text: modelData === "book" ? "Books (2)" : "Podcasts (3)" }
              }
            }
          }

          StyledText {
            Layout.fillWidth: true
            visible: !root.core.settingsView && !root.core.onHome && (root.core.listError !== "" || root.core.itemsLoading || root.core.episodesLoading
              || (root.core.openPodcast === null && root.core.visibleItems.length === 0))
            text: root.core.listError !== "" ? root.core.listError
              : (root.core.itemsLoading || root.core.episodesLoading) ? "Loading..."
              : (root.core.allItems.length === 0 ? "Nothing in your libraries yet." : "No matches.")
            color: root.core.listError !== "" ? Theme.error : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
          }

          // ---- Library / episode list ---------------------------------------
          DankListView {
            id: itemList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.core.settingsView && !root.core.onHome
            clip: true
            spacing: Theme.spacingXS
            model: root.core.openPodcast ? root.core.episodes : root.core.visibleItems
            delegate: ListRow {
              width: itemList.width
              selected: root.core.keyNav && index === root.core.cursor
              readonly property var prog: modelData.userProgress || null
              cover: root.core.openPodcast ? "" : (modelData.coverUrl || "")
              icon: root.core.openPodcast ? "graphic_eq" : (modelData.mediaType === "podcast" ? "podcasts" : "book_2")
              primary: root.core.openPodcast ? modelData.title : (modelData.media.metadata.title || "")
              secondary: root.core.openPodcast
                ? Model.formatDate(modelData.publishedAt) + (modelData.duration ? "  ·  " + Model.formatTime(modelData.duration) : "")
                  + (prog && prog.isFinished ? "  ·  Played" : (prog && prog.progress > 0 ? "  ·  " + Math.round(prog.progress * 100) + "% played" : ""))
                : (modelData.media.metadata.authorName || (modelData.mediaType === "podcast" ? "Podcast" : ""))
                  + (prog && prog.isFinished ? "  ·  Finished" : "")
              current: root.core.openPodcast
                ? (root.player.currentEpisode !== null && root.player.currentEpisode.id === modelData.id)
                : (root.player.currentItem !== null && root.player.currentItem.id === modelData.id)
              marker: root.core.openPodcast !== null && prog === null
              badge: (!root.core.openPodcast && modelData.mediaType === "podcast" && modelData.unplayedCount > 0)
                ? modelData.unplayedCount + " unplayed" : ""
              progressFraction: (prog && !prog.isFinished && prog.progress > 0) ? prog.progress : -1
              finished: prog !== null && prog.isFinished === true
              tooltip: (root.core.openPodcast || modelData.mediaType !== "podcast")
                ? (finished ? "Right-click or r / f to mark as not finished (restarts from 0:00)" : "Right-click or r / f to mark as finished")
                : ""
              onActivated: root.core.openPodcast ? root.core.playEpisode(modelData) : root.core.openItem(modelData)
              onContextActivated: {
                if (root.core.openPodcast) root.core.toggleFinished(root.core.openPodcast, modelData)
                else if (modelData.mediaType !== "podcast") root.core.toggleFinished(modelData, null)
              }
            }
          }
        }
      }
    }
  }

  // DankButton has no tooltip of its own; this shows one after a short hover,
  // the same way the list rows do. Place it inside the button.
  component HoverTip: Item {
    id: tipRoot
    property string text: ""
    // The button this sits in.
    readonly property Item host: parent
    anchors.fill: parent
    DankTooltipV2 { id: hoverTip }
    Timer {
      interval: 600
      running: tipRoot.host !== null && tipRoot.host.hovered === true && tipRoot.text !== ""
      onTriggered: hoverTip.show(tipRoot.text, tipRoot.host, 0, 0, "top")
    }
    Connections {
      target: tipRoot.host
      function onHoveredChanged() { if (!tipRoot.host.hovered) hoverTip.hide() }
    }
  }

  // ---- Now playing card (large on home, compact while browsing) -----------
  component NowPlaying: ColumnLayout {
    id: np
    property bool large: false
    spacing: Theme.spacingS

    readonly property real skipIcon: large ? Theme.iconSize + Theme.spacingXS : Theme.iconSizeSmall + Theme.spacingXS
    readonly property real skipButton: skipIcon + (large ? Theme.spacingL : Theme.spacingM)
    readonly property real playIcon: large ? Theme.iconSizeLarge + Theme.spacingS : Theme.iconSize
    readonly property real playButton: playIcon + (large ? Theme.spacingL + Theme.spacingXS : Theme.spacingL)

    readonly property string coverSrc: root.player.currentItem ? (root.player.currentItem.coverUrl || "") : ""

    // Large: cover centered, title and author below.
    Item {
      visible: np.large && root.player.hasItem && np.coverSrc !== ""
      Layout.fillWidth: true
      implicitHeight: root.coverLarge
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.coverLarge
        height: root.coverLarge
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        clip: true
        Image {
          anchors.fill: parent
          source: np.coverSrc
          sourceSize.width: root.coverLarge * 2
          sourceSize.height: root.coverLarge * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }
    }

    RowLayout {
      visible: root.player.hasItem
      Layout.fillWidth: true
      spacing: Theme.spacingM
      Rectangle {
        visible: !np.large && np.coverSrc !== ""
        Layout.preferredWidth: root.coverSmall
        Layout.preferredHeight: root.coverSmall
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        clip: true
        Image {
          anchors.fill: parent
          source: np.coverSrc
          sourceSize.width: root.coverSmall * 2
          sourceSize.height: root.coverSmall * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXXS
        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: np.large ? Text.AlignHCenter : Text.AlignLeft
          text: root.player.title
          font.pixelSize: np.large ? Theme.fontSizeLarge : Theme.fontSizeMedium
          font.weight: Font.Bold
          color: Theme.surfaceText
          elide: Text.ElideRight
        }
        StyledText {
          Layout.fillWidth: true
          visible: root.player.subtitle !== ""
          horizontalAlignment: np.large ? Text.AlignHCenter : Text.AlignLeft
          text: root.player.subtitle
          font.pixelSize: Theme.fontSizeSmall
          color: Theme.surfaceVariantText
          elide: Text.ElideRight
        }
      }
    }

    DankSlider {
      id: seek
      visible: root.player.hasItem
      Layout.fillWidth: true
      minimum: 0
      maximum: Math.max(1, Math.round(root.player.duration))
      value: Math.round(root.player.position)
      showValue: false
      wheelEnabled: false
      onSliderDragFinished: function(v) { root.player.seekTo(v) }
    }

    RowLayout {
      visible: root.player.hasItem
      Layout.fillWidth: true
      StyledText {
        text: Model.formatTime(root.player.position)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
      }
      Item { Layout.fillWidth: true }
      StyledText {
        text: root.player.loading ? "Loading..." : Model.formatTime(root.player.duration)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
      }
    }

    RowLayout {
      visible: root.player.hasItem
      Layout.fillWidth: true
      spacing: Theme.spacingS
      Item { visible: np.large; Layout.fillWidth: true }
      DankActionButton { iconName: "replay_30"; buttonSize: np.skipButton; iconSize: np.skipIcon; tooltipText: "Back 30s (h)"; onClicked: root.player.skip(-30) }
      DankActionButton {
        iconName: root.player.playing ? "pause" : "play_arrow"
        buttonSize: np.playButton
        iconSize: np.playIcon
        iconColor: Theme.primary
        tooltipText: root.player.playing ? "Pause (Space)" : "Play (Space)"
        onClicked: root.player.togglePause()
      }
      DankActionButton { iconName: "forward_30"; buttonSize: np.skipButton; iconSize: np.skipIcon; tooltipText: "Forward 30s (l)"; onClicked: root.player.skip(30) }
      Item { Layout.fillWidth: true }
      // The group doesn't move its own highlight, so currentIndex is bound to
      // root.core.speed (which also survives the popout being rebuilt).
      DankButtonGroup {
        readonly property var speeds: [0.8, 1, 1.25, 1.5, 2]
        size: "small"
        model: ["0.8x", "1x", "1.25x", "1.5x", "2x"]
        currentIndex: speeds.indexOf(root.core.speed)
        onSelectionChanged: function(index, selected) {
          if (!selected) return
          root.core.setSpeed(speeds[index])
        }
      }
    }

    DankButton {
      visible: root.player.chapters.length > 0
      Layout.fillWidth: true
      iconName: "list"
      buttonHeight: root.smallButtonHeight
      backgroundColor: Theme.surfaceContainerHigh
      textColor: Theme.surfaceText
      text: (root.core.chaptersOpen ? "Hide chapters" : "Chapters")
        + (root.player.currentChapterIndex >= 0 ? "  ·  " + root.player.chapters[root.player.currentChapterIndex].title : "")
      onClicked: root.core.chaptersOpen = !root.core.chaptersOpen
      HoverTip { text: "Show or hide chapters (c)" }
    }

    DankListView {
      id: chapterList
      visible: root.core.chaptersOpen && root.player.chapters.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, Theme.fontSizeMedium * 13)
      clip: true
      model: root.player.chapters
      delegate: ListRow {
        width: chapterList.width
        primary: modelData.title
        secondary: Model.formatTime(modelData.start)
        current: index === root.player.currentChapterIndex
        onActivated: root.player.seekTo(modelData.start)
      }
    }

    DankButton {
      visible: root.player.currentEpisode !== null && (root.player.currentEpisode.description || "") !== ""
      Layout.fillWidth: true
      iconName: "description"
      buttonHeight: root.smallButtonHeight
      backgroundColor: Theme.surfaceContainerHigh
      textColor: Theme.surfaceText
      text: root.core.notesOpen ? "Hide show notes" : "Show notes"
      onClicked: root.core.notesOpen = !root.core.notesOpen
    }

    DankFlickable {
      id: notesView
      visible: root.core.notesOpen && root.player.currentEpisode !== null && (root.player.currentEpisode.description || "") !== ""
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(notesText.implicitHeight, Theme.fontSizeMedium * 14)
      clip: true
      contentWidth: width
      contentHeight: notesText.implicitHeight
      StyledText {
        id: notesText
        width: notesView.width
        text: root.player.currentEpisode ? (root.player.currentEpisode.description || "") : ""
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
      }
    }

    StyledText {
      Layout.fillWidth: true
      visible: root.player.errorText !== ""
      text: root.player.errorText
      wrapMode: Text.WordWrap
      font.pixelSize: Theme.fontSizeSmall
      color: Theme.error
    }
  }

  // ---- One row style for library items, episodes and chapters -------------
  component ListRow: Item {
    id: row
    property string cover: ""
    property string icon: ""
    property string primary: ""
    property string secondary: ""
    property string badge: ""
    property string tooltip: ""
    property bool current: false
    property bool marker: false
    property bool finished: false
    property real progressFraction: -1
    property bool selected: false
    signal activated()
    signal contextActivated()

    readonly property real contentOpacity: finished && !current ? 0.5 : 1
    implicitHeight: Math.max(root.rowMinHeight, (cover !== "" ? root.rowCover : textCol.implicitHeight) + Theme.spacingS * 2)

    StyledRect {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: row.current ? Theme.primarySelected
        : ((mouse.containsMouse || row.selected) ? Theme.surfaceHover : "transparent")
    }
    // Keyboard selection: a thin primary-colored bar on the left edge.
    Rectangle {
      visible: row.selected
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: Theme.spacingXS
      anchors.bottomMargin: Theme.spacingXS
      width: Theme.spacingXXS
      radius: width / 2
      color: Theme.primary
    }

    Rectangle {
      id: coverBox
      visible: row.cover !== ""
      anchors.left: parent.left
      anchors.leftMargin: Theme.spacingS
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? root.rowCover : 0
      height: root.rowCover
      radius: Theme.cornerRadius
      color: Theme.surfaceContainerHigh
      clip: true
      opacity: row.contentOpacity
      Image {
        anchors.fill: parent
        source: row.cover
        sourceSize.width: root.rowCover * 2
        sourceSize.height: root.rowCover * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }
    }

    DankIcon {
      id: glyph
      visible: row.cover === "" && row.icon !== ""
      anchors.left: parent.left
      anchors.leftMargin: Theme.spacingM
      anchors.verticalCenter: parent.verticalCenter
      name: row.icon
      size: Theme.iconSize
      color: row.current ? Theme.primary : Theme.surfaceText
      opacity: row.contentOpacity
    }

    Rectangle {
      id: markerDot
      visible: row.marker
      anchors.left: glyph.visible ? glyph.right : parent.left
      anchors.leftMargin: Theme.spacingS
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.spacingS
      height: Theme.spacingS
      radius: width / 2
      color: Theme.primary
    }

    DankIcon {
      id: finishedMark
      visible: row.finished
      anchors.right: parent.right
      anchors.rightMargin: Theme.spacingM
      anchors.verticalCenter: parent.verticalCenter
      name: "check_circle"
      filled: true
      size: Theme.iconSize - 2
      color: Theme.primary
    }

    StyledRect {
      id: badgePill
      visible: row.badge !== ""
      anchors.right: parent.right
      anchors.rightMargin: Theme.spacingM
      anchors.verticalCenter: parent.verticalCenter
      width: badgeText.implicitWidth + Theme.spacingM * 2
      height: badgeText.implicitHeight + Theme.spacingXS * 2
      radius: height / 2
      color: Theme.primaryContainer
      StyledText {
        id: badgeText
        anchors.centerIn: parent
        text: row.badge
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.primary
      }
    }

    Column {
      id: textCol
      opacity: row.contentOpacity
      anchors.left: markerDot.visible ? markerDot.right
        : coverBox.visible ? coverBox.right : glyph.visible ? glyph.right : parent.left
      anchors.leftMargin: Theme.spacingM
      anchors.right: badgePill.visible ? badgePill.left : finishedMark.visible ? finishedMark.left : parent.right
      anchors.rightMargin: Theme.spacingM
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spacingXXS
      StyledText {
        width: parent.width
        text: row.primary
        font.pixelSize: Theme.fontSizeMedium
        color: row.current ? Theme.primary : Theme.surfaceText
        elide: Text.ElideRight
      }
      StyledText {
        width: parent.width
        visible: row.secondary !== ""
        text: row.secondary
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
      }
    }

    Rectangle {
      visible: row.progressFraction > 0
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: Theme.spacingS
      height: Theme.spacingXXS
      radius: height / 2
      width: (parent.width - Theme.spacingS * 2) * Math.min(1, row.progressFraction)
      color: Theme.primary
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(m) {
        if (m.button === Qt.RightButton) row.contextActivated()
        else row.activated()
      }
    }

    DankTooltipV2 {
      id: tip
    }
    Timer {
      interval: 600
      running: mouse.containsMouse && row.tooltip !== ""
      onTriggered: tip.show(row.tooltip, row, 0, 0, "top")
    }
    Connections {
      target: mouse
      function onContainsMouseChanged() { if (!mouse.containsMouse) tip.hide() }
    }
  }
}
