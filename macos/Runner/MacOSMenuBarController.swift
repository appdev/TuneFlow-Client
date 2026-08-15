import Cocoa
import FlutterMacOS

final class MacOSMenuBarButton: NSButton {
  var secondaryAction: (() -> Void)?

  override func rightMouseUp(with event: NSEvent) {
    performSecondaryActionForTesting()
  }

  func performSecondaryActionForTesting() {
    secondaryAction?()
  }
}

enum MacOSMenuBarElement: Equatable {
  case app
  case title
  case previous
  case playPause
  case next
  case favorite
}

enum MacOSMenuBarLayoutMode: Equatable {
  case full
  case compact
  case iconOnly

  init(screenWidth: CGFloat) {
    self = screenWidth >= 1440 ? .full : .compact
  }

  var visibleElements: [MacOSMenuBarElement] {
    switch self {
    case .full:
      return [.app, .title, .previous, .playPause, .next, .favorite]
    case .compact:
      return [.app, .playPause]
    case .iconOnly:
      return [.app]
    }
  }
}

enum MacOSMenuBarSizing {
  static func contentLength(
    widths: [CGFloat],
    spacing: CGFloat,
    horizontalInsets: CGFloat
  ) -> CGFloat {
    let gaps = CGFloat(max(0, widths.count - 1)) * spacing
    return max(24, ceil(widths.reduce(0, +) + gaps + horizontalInsets))
  }
}

struct MacOSMenuBarState: Equatable {
  let trackId: String
  let source: String
  let title: String
  let artist: String
  let playing: Bool
  let loading: Bool
  let canPlayPause: Bool
  let canGoPrevious: Bool
  let canGoNext: Bool
  let favorite: Bool
  let favoritePending: Bool
  let canToggleFavorite: Bool

  static let idle = MacOSMenuBarState(
    trackId: "",
    source: "",
    title: "",
    artist: "",
    playing: false,
    loading: false,
    canPlayPause: false,
    canGoPrevious: false,
    canGoNext: false,
    favorite: false,
    favoritePending: false,
    canToggleFavorite: false
  )

  init?(
    dictionary: [String: Any]
  ) {
    guard
      let trackId = dictionary["trackId"] as? String,
      let source = dictionary["source"] as? String,
      let title = dictionary["title"] as? String,
      let artist = dictionary["artist"] as? String,
      let playing = dictionary["playing"] as? Bool,
      let loading = dictionary["loading"] as? Bool,
      let canPlayPause = dictionary["canPlayPause"] as? Bool,
      let canGoPrevious = dictionary["canGoPrevious"] as? Bool,
      let canGoNext = dictionary["canGoNext"] as? Bool,
      let favorite = dictionary["favorite"] as? Bool,
      let favoritePending = dictionary["favoritePending"] as? Bool,
      let canToggleFavorite = dictionary["canToggleFavorite"] as? Bool
    else {
      return nil
    }
    self.trackId = trackId
    self.source = source
    self.title = title
    self.artist = artist
    self.playing = playing
    self.loading = loading
    self.canPlayPause = canPlayPause
    self.canGoPrevious = canGoPrevious
    self.canGoNext = canGoNext
    self.favorite = favorite
    self.favoritePending = favoritePending
    self.canToggleFavorite = canToggleFavorite
  }

  private init(
    trackId: String,
    source: String,
    title: String,
    artist: String,
    playing: Bool,
    loading: Bool,
    canPlayPause: Bool,
    canGoPrevious: Bool,
    canGoNext: Bool,
    favorite: Bool,
    favoritePending: Bool,
    canToggleFavorite: Bool
  ) {
    self.trackId = trackId
    self.source = source
    self.title = title
    self.artist = artist
    self.playing = playing
    self.loading = loading
    self.canPlayPause = canPlayPause
    self.canGoPrevious = canGoPrevious
    self.canGoNext = canGoNext
    self.favorite = favorite
    self.favoritePending = favoritePending
    self.canToggleFavorite = canToggleFavorite
  }

  var dictionary: [String: Any] {
    [
      "trackId": trackId,
      "source": source,
      "title": title,
      "artist": artist,
      "playing": playing,
      "loading": loading,
      "canPlayPause": canPlayPause,
      "canGoPrevious": canGoPrevious,
      "canGoNext": canGoNext,
      "favorite": favorite,
      "favoritePending": favoritePending,
      "canToggleFavorite": canToggleFavorite,
    ]
  }
}

enum MacOSMenuBarAction {
  case previous
  case playPause
  case next
  case toggleFavorite
  case showWindow
  case quit

  var command: String {
    switch self {
    case .previous: return "previous"
    case .playPause: return "playPause"
    case .next: return "next"
    case .toggleFavorite: return "toggleFavorite"
    case .showWindow: return "showWindow"
    case .quit: return "quit"
    }
  }
}

final class MacOSMenuBarController: NSObject {
  static let shared = MacOSMenuBarController()

  var sendCommand: ((String) -> Void)?

  private weak var mainWindow: NSWindow?
  private var channel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private let stackView = NSStackView()
  private var state = MacOSMenuBarState.idle
  private var layoutMode = MacOSMenuBarLayoutMode(
    screenWidth: NSScreen.main?.frame.width ?? 1440
  )
  private var retriedIconOnly = false

  private lazy var appButton = makeButton(
    imageName: "MenuBarTuneFlow",
    fallbackTitle: "♪",
    toolTip: "显示 TuneFlow",
    action: #selector(showWindowAction)
  )
  private lazy var titleButton: NSButton = {
    let button = makeButton(
      imageName: nil,
      fallbackTitle: "",
      toolTip: "显示当前歌曲",
      action: #selector(showWindowAction)
    )
    button.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
    return button
  }()
  private lazy var previousButton = makeButton(
    imageName: "MenuBarPrevious",
    fallbackTitle: "◀︎",
    toolTip: "上一首",
    action: #selector(previousAction)
  )
  private lazy var playPauseButton = makeButton(
    imageName: "MenuBarPlay",
    fallbackTitle: "▶︎",
    toolTip: "播放",
    action: #selector(playPauseAction)
  )
  private lazy var nextButton = makeButton(
    imageName: "MenuBarNext",
    fallbackTitle: "▶︎|",
    toolTip: "下一首",
    action: #selector(nextAction)
  )
  private lazy var favoriteButton = makeButton(
    imageName: "MenuBarHeart",
    fallbackTitle: "♡",
    toolTip: "收藏",
    action: #selector(favoriteAction)
  )

  func attach(binaryMessenger: FlutterBinaryMessenger, window: NSWindow) {
    mainWindow = window
    let channel = FlutterMethodChannel(
      name: "com.musicfree.serviceclient/macos_menu_bar",
      binaryMessenger: binaryMessenger
    )
    self.channel = channel
    sendCommand = { [weak channel] command in
      channel?.invokeMethod("command", arguments: command)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey),
      name: NSWindow.didBecomeKeyNotification,
      object: window
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose),
      name: NSWindow.willCloseNotification,
      object: window
    )
  }

  func applicationDidBecomeActive() {
    sendCommand?("applicationActivated")
  }

  func showMainWindowFromApplication() {
    showMainWindow()
  }

  func mainWindowWasHidden() {
    sendCommand?("windowHidden")
  }

  func performForTesting(_ action: MacOSMenuBarAction) {
    sendCommand?(action.command)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      createStatusItemIfNeeded()
      result(nil)
    case "updateState":
      guard
        let dictionary = call.arguments as? [String: Any],
        let next = MacOSMenuBarState(dictionary: dictionary)
      else {
        result(FlutterError(
          code: "INVALID_STATE",
          message: "Invalid macOS menu bar state",
          details: nil
        ))
        return
      }
      state = next
      updatePresentation()
      result(nil)
    case "showWindow":
      showMainWindow()
      result(nil)
    case "terminate":
      result(nil)
      DispatchQueue.main.async {
        NSApp.terminate(nil)
      }
    case "dispose":
      destroyStatusItem()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createStatusItemIfNeeded() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    stackView.orientation = .horizontal
    stackView.alignment = .centerY
    stackView.spacing = 3
    stackView.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
    if let host = item.button {
      host.target = self
      host.action = #selector(statusItemClicked)
      host.sendAction(on: [.leftMouseUp, .rightMouseUp])
      stackView.translatesAutoresizingMaskIntoConstraints = false
      host.addSubview(stackView)
      NSLayoutConstraint.activate([
        stackView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        stackView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        stackView.topAnchor.constraint(equalTo: host.topAnchor),
        stackView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      ])
    }
    rebuildLayout()
    updatePresentation()
  }

  private func destroyStatusItem() {
    guard let item = statusItem else { return }
    NSStatusBar.system.removeStatusItem(item)
    statusItem = nil
    retriedIconOnly = false
  }

  private func rebuildLayout() {
    for view in stackView.arrangedSubviews {
      stackView.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for element in layoutMode.visibleElements {
      let view: NSView
      switch element {
      case .app: view = appButton
      case .title: view = titleButton
      case .previous: view = previousButton
      case .playPause: view = playPauseButton
      case .next: view = nextButton
      case .favorite: view = favoriteButton
      }
      stackView.addArrangedSubview(view)
    }
    stackView.layoutSubtreeIfNeeded()
    updateStatusItemLength()
  }

  private func updatePresentation() {
    guard statusItem != nil else { return }
    titleButton.title = state.title
    titleButton.toolTip = state.artist.isEmpty
      ? state.title
      : "\(state.title) · \(state.artist)"
    titleButton.lineBreakMode = .byTruncatingTail

    previousButton.isEnabled = state.canGoPrevious
    nextButton.isEnabled = state.canGoNext
    playPauseButton.isEnabled = state.canPlayPause && !state.loading
    favoriteButton.isEnabled = state.canToggleFavorite && !state.favoritePending

    applyImage(
      state.playing ? "MenuBarPause" : "MenuBarPlay",
      fallbackTitle: state.playing ? "Ⅱ" : "▶︎",
      to: playPauseButton
    )
    playPauseButton.toolTip = state.loading ? "正在加载" : (state.playing ? "暂停" : "播放")
    applyImage(
      state.favorite ? "MenuBarHeartFilled" : "MenuBarHeart",
      fallbackTitle: state.favorite ? "♥︎" : "♡",
      to: favoriteButton
    )
    favoriteButton.toolTip = state.favorite ? "取消收藏" : "收藏"

    if state.trackId.isEmpty, layoutMode != .iconOnly {
      layoutMode = .iconOnly
      rebuildLayout()
    } else if !state.trackId.isEmpty, layoutMode == .iconOnly, !retriedIconOnly {
      layoutMode = MacOSMenuBarLayoutMode(
        screenWidth: NSScreen.main?.frame.width ?? 1440
      )
      rebuildLayout()
    }
    updateStatusItemLength()
    verifyVisibility()
  }

  private func updateStatusItemLength() {
    let widths = stackView.arrangedSubviews.map { view -> CGFloat in
      if view === titleButton {
        return min(160, max(0, titleButton.cell?.cellSize.width ?? 0))
      }
      if let button = view as? NSButton {
        return max(0, button.cell?.cellSize.width ?? 0)
      }
      return max(0, view.intrinsicContentSize.width)
    }
    statusItem?.length = MacOSMenuBarSizing.contentLength(
      widths: widths,
      spacing: stackView.spacing,
      horizontalInsets: stackView.edgeInsets.left + stackView.edgeInsets.right
    )
  }

  private func verifyVisibility() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let item = self.statusItem else { return }
      guard !item.isVisible, self.layoutMode != .iconOnly else { return }
      self.retriedIconOnly = true
      self.layoutMode = .iconOnly
      item.isVisible = true
      self.rebuildLayout()
    }
  }

  private func makeButton(
    imageName: String?,
    fallbackTitle: String,
    toolTip: String,
    action: Selector
  ) -> NSButton {
    let button = MacOSMenuBarButton(
      title: fallbackTitle,
      target: self,
      action: action
    )
    button.secondaryAction = { [weak self] in self?.showContextMenu() }
    button.isBordered = false
    button.bezelStyle = .inline
    button.imagePosition = .imageOnly
    button.toolTip = toolTip
    button.setAccessibilityLabel(toolTip)
    if let imageName {
      applyImage(imageName, fallbackTitle: fallbackTitle, to: button)
    } else {
      button.imagePosition = .noImage
      button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    return button
  }

  private func applyImage(
    _ name: String,
    fallbackTitle: String,
    to button: NSButton
  ) {
    guard let image = NSImage(named: name) else {
      button.image = nil
      button.imagePosition = .noImage
      button.title = fallbackTitle
      return
    }
    image.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.title = ""
  }

  @objc private func statusItemClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else {
      showMainWindow()
    }
  }

  private func showContextMenu() {
    guard let button = statusItem?.button else { return }
    let menu = NSMenu()
    let track = NSMenuItem(
      title: state.trackId.isEmpty ? "没有正在播放的歌曲" : state.title,
      action: nil,
      keyEquivalent: ""
    )
    track.isEnabled = false
    menu.addItem(track)
    menu.addItem(menuItem("上一首", #selector(previousAction), state.canGoPrevious))
    menu.addItem(menuItem(
      state.playing ? "暂停" : "播放",
      #selector(playPauseAction),
      state.canPlayPause && !state.loading
    ))
    menu.addItem(menuItem("下一首", #selector(nextAction), state.canGoNext))
    menu.addItem(menuItem(
      state.favorite ? "取消收藏" : "收藏",
      #selector(favoriteAction),
      state.canToggleFavorite && !state.favoritePending
    ))
    menu.addItem(.separator())
    menu.addItem(menuItem("显示 TuneFlow", #selector(showWindowAction), true))
    menu.addItem(menuItem("退出 TuneFlow", #selector(quitAction), true))
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: button.bounds.height),
      in: button
    )
  }

  private func menuItem(
    _ title: String,
    _ action: Selector,
    _ enabled: Bool
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = enabled
    return item
  }

  private func showMainWindow() {
    mainWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func previousAction() { performForTesting(.previous) }
  @objc private func playPauseAction() { performForTesting(.playPause) }
  @objc private func nextAction() { performForTesting(.next) }
  @objc private func favoriteAction() { performForTesting(.toggleFavorite) }
  @objc private func showWindowAction() { performForTesting(.showWindow) }
  @objc private func quitAction() { performForTesting(.quit) }
  @objc private func windowDidBecomeKey() { sendCommand?("applicationActivated") }
  @objc private func windowWillClose() { sendCommand?("windowHidden") }
}
