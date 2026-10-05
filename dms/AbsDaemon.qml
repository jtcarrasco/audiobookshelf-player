import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "Model.js" as Model

// The DankMaterialShell plugin's daemon surface. DMS creates one instance of
// it for the session, while the bar widget (AbsWidget.qml) gets one instance
// per bar. Everything that must exist once lives here: the mpv player, the
// new-episode poller, the IPC handler, the login and the library. The bar
// widgets and their popouts only render this state.
//
// The shell-independent parts (Player/MpvPlayer/PollTimer/Model.js and the
// Python backend) are shared with the Omarchy plugin at the repo root
// (tools/sync-dms.sh).
PluginComponent {
  id: root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  function backend(args) {
    return ["python3", root.pluginDir + "/scripts/abs_backend.py"].concat(args)
  }

  // ---- State ---------------------------------------------------------------
  property bool configured: false
  property string serverUrl: ""
  property string bookLibId: ""
  property string podcastLibId: ""
  property var libraries: []
  readonly property bool hasBooks: bookLibId !== ""
  readonly property bool hasPodcasts: podcastLibId !== ""
  readonly property string defaultType: hasBooks || !hasPodcasts ? "book" : "podcast"

  property var allItems: []
  property bool itemsLoading: false
  property string listError: ""
  property string filterText: ""
  property string filterType: "book"  // "book" | "podcast" | "" (search across both)
  property bool browsing: false
  property bool settingsView: false
  property var openPodcast: null
  property var episodes: []
  property bool episodesLoading: false
  property bool chaptersOpen: false
  property bool notesOpen: false
  property real speed: 1
  // Keyboard selection in the library/episode list; the highlight only shows
  // once a key has moved it.
  property int cursor: 0
  property bool keyNav: false

  property string setupError: ""
  property bool setupBusy: false
  property string pendingPassword: ""
  property bool confirmDisconnect: false

  readonly property bool onHome: !settingsView && openPodcast === null && !browsing
  readonly property var visibleItems: allItems.filter(function(it) {
    var matchesType = filterType === "" || it.mediaType === filterType
    var needle = filterText.toLowerCase()
    var title = (it.media.metadata.title || "").toLowerCase()
    var author = (it.media.metadata.authorName || "").toLowerCase()
    return matchesType && (needle === "" || title.indexOf(needle) !== -1 || author.indexOf(needle) !== -1)
  })
  readonly property var typeOptions: {
    var opts = []
    if (hasBooks) opts.push("book")
    if (hasPodcasts) opts.push("podcast")
    return opts
  }

  // ---- Actions -------------------------------------------------------------
  // The refresh icon spins while the library loads, for at least a moment.
  readonly property bool refreshing: itemsLoading || spinHold.running
  Timer { id: spinHold; interval: 600 }

  function refresh() {
    if (!configured) return
    spinHold.restart()
    if (fetchItems.running) return
    itemsLoading = true
    listError = ""
    fetchItems.running = true
  }

  function goHome() {
    if (configured) settingsView = false
    openPodcast = null
    episodes = []
    filterType = defaultType
    filterText = ""
    browsing = false
    keyNav = false
    cursor = 0
  }

  function goBack() {
    if (settingsView && configured) { settingsView = false; return true }
    if (openPodcast) { openPodcast = null; episodes = []; return true }
    if (browsing) { goHome(); return true }
    return false
  }

  function browseType(type) {
    settingsView = false
    openPodcast = null
    filterType = type
    browsing = true
  }

  function setSearch(text) {
    filterText = text
    if (text !== "" && !browsing) {
      filterType = ""
      browsing = true
    }
  }

  function openItem(item) {
    if (item.mediaType === "podcast") {
      openPodcast = item
      episodes = []
      episodesLoading = true
      fetchEpisodes.command = backend(["list-episodes", item.id])
      fetchEpisodes.running = true
    } else {
      player.playItem(item, null)
    }
  }

  function decrementUnplayed(podcastId) {
    allItems = allItems.map(function(it) {
      if (it.id !== podcastId || !(it.unplayedCount > 0)) return it
      var copy = JSON.parse(JSON.stringify(it))
      copy.unplayedCount = it.unplayedCount - 1
      return copy
    })
  }

  function playEpisode(episode) {
    if (!episode.userProgress) {
      decrementUnplayed(openPodcast.id)
      episodes = episodes.map(function(ep) {
        if (ep.id !== episode.id) return ep
        var copy = JSON.parse(JSON.stringify(ep))
        copy.userProgress = { progress: 0, isFinished: false }
        return copy
      })
    }
    player.playItem(openPodcast, episode)
  }

  // Right-click a book or episode to flip its finished state. ABS resets the
  // position to 0 when an item is marked not finished.
  function toggleFinished(item, episode) {
    var prog = (episode ? episode.userProgress : item.userProgress) || null
    var finished = !(prog && prog.isFinished)
    var key = episode ? item.id + "/" + episode.id : item.id
    finishedProcess.command = backend(["set-finished", key, finished ? "true" : "false"])
    finishedProcess.running = true
    var patch = function(obj) {
      var copy = JSON.parse(JSON.stringify(obj))
      var p = copy.userProgress || { progress: 0 }
      p.isFinished = finished
      p.progress = finished ? 1 : 0
      copy.userProgress = p
      return copy
    }
    if (episode) {
      if (!episode.userProgress) decrementUnplayed(item.id)
      episodes = episodes.map(function(ep) { return ep.id === episode.id ? patch(ep) : ep })
    } else {
      allItems = allItems.map(function(it) { return it.id === item.id ? patch(it) : it })
    }
  }

  // ---- Keyboard (same keys as the Omarchy plugin; no window toggle here) ---
  readonly property var listModel: openPodcast ? episodes : visibleItems
  readonly property bool listVisible: !settingsView && !onHome
  onOpenPodcastChanged: cursor = 0
  onFilterTypeChanged: cursor = 0
  onFilterTextChanged: cursor = 0

  function moveCursor(delta) {
    if (!listVisible || listModel.length === 0) return false
    keyNav = true
    cursor = Math.max(0, Math.min(listModel.length - 1, cursor + delta))
    return true
  }
  function jumpTo(first) {
    if (!listVisible || listModel.length === 0) return false
    keyNav = true
    cursor = first ? 0 : listModel.length - 1
    return true
  }
  // Enter: same as clicking the selected row.
  function activateSelected() {
    var it = listModel[cursor]
    if (!listVisible || !it) return false
    if (openPodcast) playEpisode(it)
    else openItem(it)
    return true
  }
  // r / f: same as right-clicking the selected row.
  function toggleFinishedSelected() {
    var it = listModel[cursor]
    if (!listVisible || !it) return
    if (openPodcast) toggleFinished(openPodcast, it)
    else if (it.mediaType !== "podcast") toggleFinished(it, null)
  }
  function skipChapter(direction) {
    var target = Model.chapterSeekTarget(player.chapters, player.position, direction)
    if (target >= 0) player.seekTo(target)
  }
  function setSpeed(value) {
    speed = value
    player.mpv.setSpeed(value)
  }
  function cycleType() {
    if (!browsing || openPodcast || typeOptions.length < 2) return
    filterType = filterType === "book" ? "podcast" : "book"
  }

  readonly property var keyHelp: [
    { key: "j / k", action: "Move down / up the list" },
    { key: "Home / End", action: "First / last item" },
    { key: "Enter", action: "Play, or open a podcast" },
    { key: "r / f", action: "Toggle finished" },
    { key: "1 / 2 / 3", action: "Home / Books / Podcasts" },
    { key: "Tab", action: "Switch Books / Podcasts" },
    { key: "Space", action: "Play / pause" },
    { key: "h / l", action: "Back / forward 30s" },
    { key: "n / p", action: "Next / previous chapter" },
    { key: "[ / ]", action: "Slower / faster" },
    { key: "c", action: "Show chapters" },
    { key: "/ or a", action: "Search" },
    { key: "q / R", action: "Refresh library" },
    { key: ",", action: "Settings" },
    { key: "Esc", action: "Back, then close" },
    { key: "Right-click", action: "Toggle finished on a row" }
  ]

  function chooseLibrary(mediaType, id) {
    if (mediaType === "book") bookLibId = id
    else podcastLibId = id
    setLibraries.command = backend(["set-libraries", bookLibId, podcastLibId])
    setLibraries.running = true
  }

  function librariesOfType(mediaType) {
    return libraries.filter(function(l) { return l.mediaType === mediaType })
  }

  onDefaultTypeChanged: if (!browsing) filterType = defaultType
  onSettingsViewChanged: if (settingsView && configured) listLibraries.running = true

  Component.onCompleted: checkConfigured.running = true

  // ---- Player + background work --------------------------------------------
  readonly property alias player: playerItem
  readonly property alias poller: pollerItem

  Player { id: playerItem }

  PollTimer {
    id: pollerItem
    pollMinutes: 20
    notifyCommand: ["dms", "notify"]
  }

  IpcHandler {
    target: "absPlayer"
    function toggle(): void { root.togglePopout() }
    function playPause(): void { root.player.togglePause() }
    function browse(type: string): void { root.browseType(type) }
    function search(query: string): void { root.setSearch(query) }
    function home(): void { root.goHome() }
  }

  // ---- Backend processes ---------------------------------------------------
  Process {
    id: checkConfigured
    command: root.backend(["check-configured"])
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          root.configured = r.configured === true
          root.serverUrl = r.baseUrl || ""
          root.bookLibId = r.libraryId || ""
          root.podcastLibId = r.podcastLibraryId || ""
        } catch (e) {}
        if (!root.configured) root.settingsView = true
        else root.refresh()
      }
    }
  }

  Process {
    id: fetchItems
    command: root.backend(["list-items"])
    stdout: StdioCollector {
      onStreamFinished: {
        root.itemsLoading = false
        try {
          var parsed = JSON.parse(text)
          if (parsed && parsed.error) { root.listError = parsed.error; return }
          root.allItems = parsed
        } catch (e) {
          root.listError = "Couldn't read the library from the backend"
        }
      }
    }
  }

  Process {
    id: fetchEpisodes
    stdout: StdioCollector {
      onStreamFinished: {
        root.episodesLoading = false
        try {
          var parsed = JSON.parse(text)
          if (parsed && parsed.error) { root.listError = parsed.error; return }
          root.episodes = parsed
        } catch (e) {
          root.listError = "Couldn't read the episode list"
        }
      }
    }
  }

  Process {
    id: finishedProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try { var r = JSON.parse(text); if (r.error) root.listError = r.error } catch (e) {}
      }
    }
  }

  Process {
    id: mpvCheck
    command: root.backend(["check-mpv"])
    stdout: StdioCollector {
      onStreamFinished: {
        var installed = false
        try { installed = JSON.parse(text).installed === true } catch (e) {}
        if (!installed) {
          root.setupBusy = false
          root.pendingPassword = ""
          root.setupError = "mpv is required but not installed. Install the mpv package, then connect again."
          return
        }
        loginProcess.running = true
      }
    }
  }

  property string loginUrl: ""
  // The popout clears its password field when this fires.
  signal loginSucceeded()
  property string loginUser: ""

  Process {
    id: loginProcess
    // stdin stays enabled for the life of this Process (Quickshell never
    // re-enables it once closed); the backend reads one line per attempt.
    stdinEnabled: true
    command: root.backend(["login", root.loginUrl, root.loginUser])
    onStarted: {
      write(root.pendingPassword + "\n")
      root.pendingPassword = ""
    }
    stdout: StdioCollector {
      onStreamFinished: {
        root.setupBusy = false
        try {
          var result = JSON.parse(text)
          if (result.ok) {
            root.serverUrl = result.baseUrl || root.loginUrl.replace(/\/+$/, "")
            root.libraries = result.libraries || []
            root.bookLibId = result.libraryId || ""
            root.podcastLibId = result.podcastLibraryId || ""
            root.configured = true
            root.settingsView = false
            root.allItems = []
            root.loginSucceeded()
            root.refresh()
          } else {
            root.setupError = result.error || "Connection failed"
          }
        } catch (e) {
          root.setupError = "Unexpected response from the backend"
        }
      }
    }
  }

  Process {
    id: listLibraries
    command: root.backend(["list-libraries"])
    stdout: StdioCollector {
      onStreamFinished: {
        try { var r = JSON.parse(text); if (!r.error) root.libraries = r.libraries || [] } catch (e) {}
      }
    }
  }

  Process {
    id: setLibraries
    stdout: StdioCollector {
      onStreamFinished: { root.allItems = []; root.refresh() }
    }
  }

  Process {
    id: disconnectProcess
    command: root.backend(["disconnect"])
    stdout: StdioCollector {
      onStreamFinished: {
        root.player.reset()
        root.configured = false
        root.serverUrl = ""
        root.bookLibId = ""
        root.podcastLibId = ""
        root.libraries = []
        root.allItems = []
        root.episodes = []
        root.openPodcast = null
        root.browsing = false
        root.confirmDisconnect = false
        root.settingsView = true
      }
    }
  }

  Timer {
    id: confirmTimer
    interval: 4000
    onTriggered: root.confirmDisconnect = false
  }

  // ---- Called from the popout ----------------------------------------------
  function login(url, user, password) {
    if (setupBusy) return
    setupError = ""
    setupBusy = true
    loginUrl = url
    loginUser = user
    pendingPassword = password
    mpvCheck.running = true
  }

  // First click arms the button, a second within 4s disconnects.
  function disconnectClicked() {
    if (!confirmDisconnect) {
      confirmDisconnect = true
      confirmTimer.restart()
      return
    }
    confirmTimer.stop()
    disconnectProcess.running = true
  }

  // ---- Bar widgets ---------------------------------------------------------
  // Every bar shows its own copy of the widget. They register here so the
  // toggle IPC call opens the popout on the focused screen only.
  property var views: []

  function registerView(view) {
    if (views.indexOf(view) === -1) views = views.concat([view])
  }

  function unregisterView(view) {
    views = views.filter(function(v) { return v !== view })
  }

  function togglePopout() {
    var focused = BarWidgetService.getFocusedScreenName()
    var target = views.find(function(v) { return v.parentScreen && v.parentScreen.name === focused }) || views[0]
    if (target) target.triggerPopout()
  }
}
