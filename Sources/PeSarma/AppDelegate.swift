import AppKit
import Carbon
import Combine
import Quartz
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let line = Line()
    private var panel: LinePanel!
    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher!
    /// In inbox mode, a second watcher on the Desktop. If a macOS version
    /// ignores the screenshot settings (macOS 27 renamed one), captures keep
    /// landing on the Desktop, and they still hang on the line.
    /// Folders chosen in "Also watch folders", like the one another
    /// screenshot app saves to.
    private var folderWatchers: [ScreenshotWatcher] = []
    private var clipboardWatcher: ClipboardWatcher!
    private var noteWatcher: NoteWatcher!
    private var signalSources: [DispatchSourceSignal] = []
    private var hotKey: HotKey?
    /// ⌃⌥F searches the line. Fixed, apart from the shortcut that shows it.
    private var searchHotKey: HotKey?
    private var searchBar: SearchBar!
    private let zoom = Zoom()
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?

    /// Whether the panel is ordered in. It can be in and still tucked away
    /// above the top edge, like an auto-hiding Dock.
    private var isPresent = false
    /// Whether the line has slid down into view.
    private var isRevealed = false
    /// Opened on purpose with the shortcut or the menu: it stays down until
    /// the cursor has visited it and left, or the shortcut is pressed again.
    private var pinned = false
    /// A new screenshot shows itself for a moment, then tucks away.
    private var peekUntil = Date.distantPast
    private var hotZoneSince: Date?
    /// After a click in the menu bar the line stays up there hidden until the
    /// pointer leaves the menu bar, so it does not come back over a menu.
    private var menuBarSuppressed = false
    private var clickMonitors: [Any] = []
    private var awaySince: Date?
    /// Whether the line should be up, if nothing prevents it. A full screen
    /// app on that screen does: the line waits until you leave full screen.
    private var wanted = false
    /// Set when you open the line on purpose, so it stays up while empty.
    private var keepOpen = false
    /// Opened on purpose with the shortcut or the menu, which counts over a
    /// full screen app too, until the line tucks away.
    private var openedOnPurpose = false

    // What brings the line down, from the menu bar's "Bring the line down".
    // Out of the box, the first two are on and the third off.

    /// Resting the pointer in the menu bar. Off, only the shortcut and the
    /// menu open it.
    static var opensFromMenuBar: Bool {
        get { !UserDefaults.standard.bool(forKey: "menuBarRevealOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "menuBarRevealOff") }
    }

    /// Something new hanging shows itself for a moment. Off, it hangs
    /// quietly and waits for you to bring the line down.
    static var peeksAtNew: Bool {
        get { !UserDefaults.standard.bool(forKey: "quietHang") }
        set { UserDefaults.standard.set(!newValue, forKey: "quietHang") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.log(.info, "app.start", ["inbox": "\(Inbox.isEnabled)", "locale": AppLanguage.active, "languageChosen": AppLanguage.chosen ?? "system"])
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        panel = LinePanel(content: host)
        panel.placeOnScreen()
        updateCapacity()

        if Inbox.isEnabled { Inbox.apply() }
        restoreSettingsOnTermination()
        #if MENU_PROBE
        installMenuProbe()
        #endif
        startWatcher()
        clipboardWatcher = ClipboardWatcher { [weak self] url in self?.hangCapture(url) }
        if ClipboardWatcher.isEnabled { clipboardWatcher.start() }
        noteWatcher = NoteWatcher { [weak self] in self?.line.refreshNotes() }
        noteWatcher.start()

        registerShortcut()
        searchBar = SearchBar(line: line)
        searchBar.onReturn = { [weak self] in self?.copyFirstMatch() }
        searchBar.onEnd = { [weak self] in self?.endSearch(tuckAway: true) }
        registerSearchShortcut()

        setUpStatusItem()
        watchMenuBarClicks()
        watchPutBackKey()

        // Hang on Pe sârmă, in the menu of images in Finder and other apps.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        Markup.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        Share.shared.clearAll()
        Trim.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        panel.onScroll = { [weak self] event in
            // Sideways on a trackpad, or the wheel of a mouse.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            self?.line.scroll(by: event.hasPreciseScrollingDeltas ? delta : delta * 12)
        }
        line.onFall = { [weak self] item in self?.fall(item) }
        line.onHold = { [weak self] id in self?.hold(id) }
        line.onHangBack = { id in Held.hangBack(id) }
        line.onUndoableAction = { [weak self] in self?.keepUndoAtPointer() }

        line.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.itemsChanged() }
            .store(in: &cancellables)
        // Photos kept from last time show themselves for a moment.
        if line.liveCount > 0 { comeDown(on: nil) }

        // Entering or leaving full screen switches Space. Check again once the
        // switch animation has settled.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Opened on purpose counts for the Space it was opened on.
                    if name == NSWorkspace.activeSpaceDidChangeNotification { self?.openedOnPurpose = false }
                    self?.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.refresh()
                        self?.keepOnActiveSpace()
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.placeOnScreen()
                self?.updateCapacity()
            }
        }

        if !Inbox.wasOffered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.offerInbox()
                self?.offerCopying()
            }
        } else if !Self.copyingOffered {
            // Updated from a version that only hung screenshots: shown once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.offerCopying() }
        } else if Self.shouldOfferLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Self.offerLogin() }
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            keepOpen = true
            wanted = true
            refresh()
            reveal(pinned: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.line.liveCount == 0 else { return }
                self.keepOpen = false
                self.wanted = false
                self.refresh()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
        Diag.log(.info, "app.quit", ["settingsRestored": "\(!Inbox.isApplied)"])
        Diag.flush()
        Share.shared.clearAll()
    }

    // MARK: Inbox mode

    private func startWatcher() {
        watcher?.stop()
        watcher = ScreenshotWatcher(
            onNew: { [weak self] url in self?.hangCapture(url, screenshot: true) },
            onChange: { [weak self] in self?.line.prune() })
        watcher.start()
        folderWatchers.forEach { $0.stop() }
        folderWatchers = []
        // A folder may also be watched for screenshots, like the Desktop; an
        // image both report hangs once.
        for folder in Self.extraFolders {
            let extra = ScreenshotWatcher(
                folder: folder, anyImage: true,
                onNew: { [weak self] url in self?.hangCapture(url) },
                onChange: { [weak self] in self?.line.prune() })
            extra.start()
            folderWatchers.append(extra)
        }
    }

    /// Up to three folders: enough for another screenshot app or an export
    /// folder, few enough that screenshots still have room on the line.
    static let maxExtraFolders = 3

    /// The folders from "Also watch folders" that still exist. New images in
    /// them hang like screenshots; taking one down leaves the file there.
    static var extraFolders: [URL] {
        get {
            let paths = UserDefaults.standard.stringArray(forKey: "extraFolders") ?? []
            return paths.compactMap { path in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        set { UserDefaults.standard.set(newValue.map(\.path), forKey: "extraFolders") }
    }

    /// Each new screenshot goes to the clipboard as it hangs.
    static var copiesScreenshots: Bool {
        get { UserDefaults.standard.bool(forKey: "copyScreenshots") }
        set { UserDefaults.standard.set(newValue, forKey: "copyScreenshots") }
    }

    private func chooseExtraFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Watch")
        panel.message = L("New images saved to this folder will hang on the line.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, Self.extraFolders.count < Self.maxExtraFolders,
              !Self.extraFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        Self.extraFolders.append(url)
        startWatcher()
    }

    private func setInbox(_ on: Bool) {
        Inbox.isEnabled = on
        if on { Inbox.apply() } else { Inbox.restore() }
        startWatcher()
    }

    /// Asked once. Changing system settings is the user's call, never ours.
    private func offerInbox() {
        Inbox.wasOffered = true
        let alert = NSAlert()
        alert.messageText = L("Let Pe sârmă handle your screenshots?")
        alert.informativeText = L(
            "Screenshots will hang on the line the instant you take them, without the floating thumbnail, and will not pile up on your Desktop. Drag one to a folder to keep it, or discard it with the cross. You can turn this off from the menu bar, and your settings come back when Pe sârmă quits.")
        alert.addButton(withTitle: L("Turn on"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSImage(named: "PeSarma") ?? NSApp.applicationIconImage { alert.icon = icon }
        // A menu bar app that does not open at login is gone after the first
        // restart, so the first launch offers it too, ticked.
        let login = Self.shouldOfferLogin ? NSButton(checkboxWithTitle: L("Open at login"), target: nil, action: nil) : nil
        if let login {
            login.state = .on
            alert.accessoryView = login
            Self.loginOffered()
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { setInbox(true) }
        if login?.state == .on { Self.openAtLogin() }
    }

    // MARK: Hang what you copy

    private static let copyingOfferedKey = "copyingOffered"
    private static var copyingOffered: Bool {
        get { UserDefaults.standard.bool(forKey: copyingOfferedKey) }
        set { UserDefaults.standard.set(newValue, forKey: copyingOfferedKey) }
    }

    /// Asked once, on the first launch or the first after an update: what
    /// you copy can hang too. Each kind is ticked and shown, but nothing is
    /// kept until Turn on. Open at login rides along when it is due, so an
    /// update asks one thing, not two.
    private func offerCopying() {
        Self.copyingOffered = true
        let alert = NSAlert()
        alert.messageText = L("Hang what you copy too?")
        alert.informativeText = L("Images, text and links you copy can hang on the line as well: text as a note, a link with its site. They stay on this Mac, and nothing is ever kept from a password field. Change it anytime under Hang what you copy in the menu bar.")
        alert.addButton(withTitle: L("Turn on"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSImage(named: "PeSarma") ?? NSApp.applicationIconImage { alert.icon = icon }
        let kinds: [(String, ReferenceWritableKeyPath<ClipboardWatcher.Type, Bool>)] = [
            (L("Images"), \.imagesEnabled), (L("Text"), \.textEnabled), (L("Links"), \.linksEnabled),
        ]
        let boxes = kinds.map { kind -> NSButton in
            let box = NSButton(checkboxWithTitle: kind.0, target: nil, action: nil)
            box.state = .on
            return box
        }
        let login = Self.shouldOfferLogin ? NSButton(checkboxWithTitle: L("Open at login"), target: nil, action: nil) : nil
        login?.state = .on
        if login != nil { Self.loginOffered() }
        let stack = NSStackView(views: boxes + (login.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        // Open at login is a separate question: a little apart.
        if login != nil { stack.setCustomSpacing(14, after: boxes[boxes.count - 1]) }
        stack.frame = NSRect(x: 0, y: 0, width: 240, height: stack.fittingSize.height)
        alert.accessoryView = stack
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            for (kind, box) in zip(kinds, boxes) { ClipboardWatcher.self[keyPath: kind.1] = box.state == .on }
            refreshClipboardWatcher()
        }
        if login?.state == .on { Self.openAtLogin() }
    }

    // MARK: Open at login

    private static let loginOfferedKey = "loginOfferedVersion"
    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Each install or update asks once whether Pe sârmă should open at
    /// login, unless it already does.
    private static var shouldOfferLogin: Bool {
        SMAppService.mainApp.status != .enabled
            && UserDefaults.standard.string(forKey: loginOfferedKey) != version
    }

    private static func loginOffered() {
        UserDefaults.standard.set(version, forKey: loginOfferedKey)
    }

    private static func offerLogin() {
        loginOffered()
        let alert = NSAlert()
        alert.messageText = L("Open Pe sârmă at login?")
        alert.informativeText = L("Pe sârmă does not open when you log in, so after a restart the line is gone until you open it again.")
        alert.addButton(withTitle: L("Open at login"))
        alert.addButton(withTitle: L("Not now"))
        if let icon = NSImage(named: "PeSarma") ?? NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openAtLogin() }
    }

    /// Turned off in System Settings, macOS asks for approval there.
    private static func openAtLogin() {
        guard SMAppService.mainApp.status != .enabled else { return }
        toggleLaunchAtLogin()
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Watching the clipboard is opt in, from the menu bar only.
    private func refreshClipboardWatcher() {
        if ClipboardWatcher.isEnabled { clipboardWatcher.start() } else { clipboardWatcher.stop() }
        updateStatusIcon()
    }

    /// Quitting from the menu or logging out runs applicationWillTerminate.
    /// A plain kill does not, so settings are also restored on those signals.
    private func restoreSettingsOnTermination() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                if Inbox.isEnabled { Inbox.restore() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Showing and hiding

    /// An empty line goes away, unless it was opened on purpose.
    private func itemsChanged() {
        updateStatusIcon()
        Held.forget(except: Set(line.items.filter { !$0.falling && $0.held }.map(\.id)))
        guard line.liveCount == 0, !keepOpen, undoAnchor == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.line.liveCount == 0, !self.keepOpen, self.undoAnchor == nil else { return }
            self.wanted = false
            self.refresh()
        }
    }

    /// The line comes down on that screen for a moment, then tucks away.
    /// Without a screen, it uses the one under the pointer.
    private func comeDown(on screen: NSScreen?) {
        panel.placeOnScreen(screen)
        updateCapacity()
        wanted = true
        refresh()
        if Self.peeksAtNew { reveal(peekFor: 2.5) }
    }

    // MARK: The capture flying to the line

    /// A new screenshot lifts off from where it was taken and flies to its
    /// place on the line. Without a known capture area it simply drops in.
    private func hangCapture(_ url: URL, screenshot: Bool = false) {
        // Several watchers may report a file we just saved. Keep ignoring
        // that same file after either a move or a copy.
        guard !line.isDesktopSave(url) else { return }
        // Already hanging: a photo put back with ⌘Z comes out of the Trash
        // into the folder, and the watcher sees it arrive. It must not pull
        // the line over to the screen it was first taken on.
        guard !line.items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL && !$0.falling })
        else { return }
        let from = captureRect(of: url)
        let screen = from.flatMap { from in
            NSScreen.screens.first { NSMouseInRect(CGPoint(x: from.midX, y: from.midY), $0.frame, false) }
        }
        // Every capture brings the line down before it hangs, on the screen it
        // was taken on. On a full line the oldest photo then falls in view as
        // the new one flies in.
        comeDown(on: screen)
        // A screenshot macOS took already played its shutter, so it hangs
        // without a chime of its own. Copied images and watched folders,
        // which come with no sound, keep it.
        guard let id = line.hang(url, quietly: from != nil, flying: from != nil) else {
            // Nothing hung after all, so an empty line goes away again.
            itemsChanged()
            return
        }
        // Recordings hang from the same folder, but the option is for screenshots.
        if screenshot, Self.copiesScreenshots, !isRecording(url) { line.copy(id) }
        guard let from else { return }
        // Let the line come down and lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: from)
        }
    }

    private func fly(_ id: UUID, from: CGRect) {
        guard isPresent, isRevealed, !Self.reducesMotion, CaptureFlight.flightsInProgress < 2,
              let screen = panel.screen,
              let to = cardFrame(for: id),
              let item = line.items.first(where: { $0.id == id }) else {
            line.land(id)
            return
        }
        // Sharp enough while it starts out at the captured size, which a
        // full Retina screen would otherwise take at full resolution.
        let pixels = Int(max(from.width, from.height) * screen.backingScaleFactor)
        guard let image = makeThumbnail(item.url, maxPixels: min(1500, max(400, pixels)))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            line.land(id)
            return
        }
        CaptureFlight.fly(image: image, from: from, to: to, tilt: CGFloat(item.tilt), on: screen) { [weak self] in
            self?.line.land(id)
        }
    }

    /// A discarded card falls over the whole screen, from where it hangs.
    /// Reduce motion in Accessibility settings: photos land and leave
    /// without flying across the screen or falling down it.
    private static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func fall(_ item: Pegged) {
        guard isPresent, isRevealed, !item.flying, !Self.reducesMotion, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        CaptureFlight.fall(image: image, card: card, tilt: CGFloat(item.tilt), pinned: item.kept, on: screen)
    }

    /// Where a card will hang, in screen coordinates, using the same layout
    /// as the line view.
    private func cardFrame(for id: UUID) -> CGRect? {
        guard let index = line.items.firstIndex(where: { $0.id == id }) else { return nil }
        let width = panel.frame.width
        let x = Layout.x(index: index, count: line.items.count, width: width,
                         visible: line.visibleCount, scroll: line.scroll, pinned: line.pinnedLead)
        let viewTop = Layout.ropeY(x: x, width: width) - Layout.pinAbove
        let cardTop = viewTop + PeggedView.cardOffsetBelowTop
        let size = PeggedView.cardSize(for: line.items[index].thumb.size)
        return CGRect(x: panel.frame.minX + x - size.width / 2,
                      y: panel.frame.maxY - cardTop - size.height,
                      width: size.width, height: size.height)
    }

    /// Decides whether the panel is ordered in at all: something to show,
    /// and no full screen app on that screen unless you asked for the line.
    private func refresh() {
        let blocked = !openedOnPurpose && (panel.screen.map(FullScreen.blocksLine(on:))
            ?? LinePanel.screenUnderPointer().map(FullScreen.blocksLine(on:)) ?? false)
        if wanted && !blocked {
            present()
        } else {
            dismiss()
        }
        // The cursor is watched while there is a line, even tucked away,
        // to notice it pushing against the top edge.
        if wanted { startMouseTracking() } else { stopMouseTracking() }
    }

    private func present() {
        guard !isPresent else { return }
        isPresent = true
        panel.alphaValue = 1
        // The window itself only comes in while the line is down; see setRevealed.
        if isRevealed { panel.orderFrontRegardless() }
    }

    private func dismiss() {
        guard isPresent else { return }
        isPresent = false
        setRevealed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isPresent else { return }
            self.panel.orderOut(nil)
        }
    }

    /// The line is one window on every Space. After a long time running,
    /// macOS can leave it bound to a single Space, where ordering it in does
    /// nothing on the others while captures keep arriving (#80). Quitting and
    /// opening the app again fixes it because the window is new, so do the
    /// same here: a fresh window with the same contents, in the same place.
    private func keepOnActiveSpace() {
        guard isPresent, isRevealed, panel.isVisible, !panel.isOnActiveSpace else { return }
        log.notice("The line was not on the active Space; making its window again")
        let old = panel!
        let content = old.contentView
        old.contentView = NSView()
        old.orderOut(nil)
        let fresh = LinePanel(content: content ?? NSView())
        fresh.onScroll = old.onScroll
        fresh.setFrame(old.frame, display: false)
        fresh.ignoresMouseEvents = old.ignoresMouseEvents
        fresh.alphaValue = old.alphaValue
        panel = fresh
        fresh.orderFrontRegardless()
    }

    private func reveal(pinned: Bool = false, peekFor seconds: TimeInterval = 0) {
        guard isPresent else { return }
        if pinned { self.pinned = true }
        if seconds > 0 { peekUntil = Date().addingTimeInterval(seconds) }
        awaySince = nil
        setRevealed(true)
    }

    private func setRevealed(_ on: Bool) {
        guard on != isRevealed else { return }
        isRevealed = on
        line.revealed = on
        // It always comes down showing the newest.
        if on { line.scroll = 0 }
        // Tucked away, the line leaves no window behind: an invisible strip
        // over the top of the screen would still sit above other apps for
        // anything that checks what is on top, like screen automation.
        if on {
            if isPresent {
                panel.orderFrontRegardless()
                DispatchQueue.main.async { [weak self] in self?.keepOnActiveSpace() }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.isRevealed else { return }
                self.panel.orderOut(nil)
            }
        }
        if !on {
            // Tucked away by any means, a search under way ends with it.
            if searchBar?.isShown == true { endSearch(tuckAway: false) }
            zoom.hide()
            undoAnchor = nil
            holdPutBackKey(false)
            line.clearSelection()
            holdSelectionKeys(false)
            pinned = false
            peekUntil = .distantPast
            panel.ignoresMouseEvents = true
            // Opened on purpose lasts until the line tucks away, however that
            // happens: an empty line then goes, as with the shortcut, and over
            // a full screen app the line goes too.
            if keepOpen || openedOnPurpose {
                keepOpen = false
                openedOnPurpose = false
                if line.liveCount == 0 { wanted = false }
                refresh()
            }
        }
    }

    // MARK: Searching the line


    /// Brings the line down and opens the search field under it.
    private func startSearch() {
        if !isRevealed { toggle() }
        keepOpen = true
        pinned = true
        searchBar.show(below: panel.frame)
    }

    /// Return copies the newest photo, note or link that matches, and the
    /// line goes back up, as after picking a result in Spotlight.
    private func copyFirstMatch() {
        guard line.isSearching, let item = line.shown.last(where: { !$0.falling }) else { return }
        line.copy(item.id)
        endSearch(tuckAway: true)
    }

    /// The whole line comes back. With Escape it also tucks away; after a
    /// click elsewhere it stays as it is.
    private func endSearch(tuckAway: Bool) {
        line.query = ""
        searchBar.hide()
        if tuckAway, isRevealed { setRevealed(false) }
    }

    @objc private func toggle() {
        if isRevealed {
            setRevealed(false)
        } else {
            keepOpen = true
            wanted = true
            openedOnPurpose = true
            panel.placeOnScreen()
            updateCapacity()
            refresh()
            reveal(pinned: true)
        }
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel.ignoresMouseEvents = true
        holdPutBackKey(false)
        holdPhotoKeys(over: nil)
        holdSelectionKeys(false)
    }

    /// How long the cursor rests against the top edge before the line comes
    /// down. Short enough to feel instant, long enough that a quick trip to
    /// the menu bar does not trigger it.
    private static let revealDelay: TimeInterval = 0.25

    /// The menu bar strip at the top of a screen. With an auto-hiding menu
    /// bar the visible frame reaches the top, so the system thickness is used.
    static func menuBarBand(of screen: NSScreen) -> NSRect {
        var h = screen.frame.maxY - screen.visibleFrame.maxY
        if h < 1 { h = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }

    /// The part of the menu bar that brings the line down: the middle third,
    /// so the menus on the left and the icons on the right stay easy to reach.
    static func revealBand(of screen: NSScreen) -> NSRect {
        let bar = menuBarBand(of: screen)
        let width = bar.width / 3
        return NSRect(x: bar.midX - width / 2, y: bar.minY, width: width, height: bar.height)
    }

    /// A click anywhere in the top bar of any screen, a menu or an icon, puts the line away.
    private func watchMenuBarClicks() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A new click ends the previous menu interaction. If this
                // click performs another undoable action it gets a new anchor.
                self.releaseUndoAnchor()
                let p = NSEvent.mouseLocation
                guard NSScreen.screens.contains(where: { NSMouseInRect(p, Self.menuBarBand(of: $0), false) }) else { return }
                self.menuBarSuppressed = true
                self.hotZoneSince = nil
                if self.isRevealed {
                    self.pinned = false
                    self.setRevealed(false)
                }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in handler(e); return e }) {
            clickMonitors.append(local)
        }
    }
    /// How long the cursor is away before the line tucks back up.
    private static let retractDelay: TimeInterval = 0.5

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()

        let screenUnderPointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inMenuBar = screenUnderPointer.map { NSMouseInRect(mouse, Self.menuBarBand(of: $0), false) } ?? false
        if !inMenuBar { menuBarSuppressed = false }
        let inRevealBand = screenUnderPointer.map { NSMouseInRect(mouse, Self.revealBand(of: $0), false) } ?? false

        guard isRevealed else {
            holdPutBackKey(false)
            holdPhotoKeys(over: nil)
            holdSelectionKeys(false)
            line.closeGaps()
            // Resting in the middle of the menu bar brings the line down on
            // that screen. Pushing against the top edge is part of it, and it
            // also works when another display sits above and the pointer
            // never stops.
            // An empty line stays up there: only the shortcut and the menu
            // bring it down on purpose.
            if line.liveCount > 0, Self.opensFromMenuBar, let screen = screenUnderPointer,
               inRevealBand, !menuBarSuppressed, !FullScreen.blocksLine(on: screen) {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    if panel.screen != screen {
                        panel.placeOnScreen()
                        updateCapacity()
                    }
                    refresh()
                    reveal()
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        updateMousePassThrough(mouse)
        updateZoom(mouse)

        // The line's zone runs from its lowest point up to the top of the
        // screen, menu bar included, so moving up never hides it.
        var zone = panel.frame
        if let screen = panel.screen { zone.size.height = screen.frame.maxY - zone.minY }
        let inside = NSMouseInRect(mouse, zone, false)
        // While searching, the keys belong to the search field: Space and
        // Delete type, and ⌘Z undoes typing.
        let searching = searchBar?.isShown == true
        let atUndoAnchor = isAtUndoAnchor(mouse)
        if inside && pinned && !searching { pinned = false }
        holdPutBackKey((inside || atUndoAnchor) && !searching && !GrabView.isShowingMenu && !Share.shared.isOpen)
        holdPhotoKeys(over: inside && !searching ? photo(under: mouse) : nil)
        holdSelectionKeys(inside && !searching && !GrabView.isShowingMenu && !Share.shared.isOpen)
        // Gaps left by discarded photos close once the pointer moves away.
        if !inside { line.closeGaps() }

        // A search keeps the line down until Escape or a click elsewhere.
        let busy = pinned || searching || atUndoAnchor || GrabView.isDragging || GrabView.isShowingMenu || Share.shared.isOpen
            || line.pressedID != nil || now < peekUntil
        if inside || busy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                setRevealed(false)
            }
        }
    }

    /// The card under the pointer opens larger below the line. Not while
    /// dragging, in a card's menu, or while one of our windows is in front,
    /// like Quick Look.
    private func updateZoom(_ mouse: NSPoint) {
        guard Zoom.isEnabled, !GrabView.isDragging, !GrabView.isShowingMenu, NSApp.keyWindow == nil,
              let screen = panel.screen else {
            zoom.hide()
            return
        }
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        let hit = line.hitRects.first { $0.value.contains(flipped) }
        let item = hit.flatMap { hit in line.items.first { $0.id == hit.key && !$0.falling && !$0.flying } }
        let card = hit.map {
            CGRect(x: panel.frame.minX + $0.value.minX, y: panel.frame.maxY - $0.value.maxY,
                   width: $0.value.width, height: $0.value.height)
        }
        zoom.update(item, card: card, on: screen)
    }

    /// The panel spans the whole width of the screen, so it only accepts the
    /// mouse while the cursor is over a photo. Everywhere else, clicks go to
    /// whatever is underneath.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard !GrabView.isDragging else { return }
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        var overPhoto = line.hitRects.values.contains { $0.insetBy(dx: -4, dy: -4).contains(flipped) }
        // A line longer than the screen also takes the band the photos hang
        // in, gaps included, so a swipe anywhere along it moves it.
        if !overPhoto, line.items.count > line.visibleCount, Line.keepOnLine != nil {
            let band = line.hitRects.values.reduce(CGRect.null) { $0.union($1) }
            overPhoto = !band.isNull && flipped.y >= band.minY - 4 && flipped.y <= band.maxY + 4
        }
        if panel.ignoresMouseEvents == overPhoto {
            panel.ignoresMouseEvents = !overPhoto
        }
    }

    // MARK: Holding

    /// Takes a photo off the line to hold in front of you. The line goes
    /// up, so it is out of the way of the photo you are looking at.
    private func hold(_ id: UUID) {
        guard let item = line.items.first(where: { $0.id == id && !$0.falling && !$0.held }) else { return }
        line.setHeld(id, true)
        Held.show(id, url: item.url, line: line) { [weak self] id, frame in self?.hangBack(id, from: frame) }
    }

    /// Back onto its clip: the line comes down and the photo flies home.
    private func hangBack(_ id: UUID, from frame: CGRect) {
        line.setHeld(id, false)
        comeDown(on: NSScreen.screens.first { $0.frame.intersects(frame) })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: frame)
        }
    }

    // MARK: Hang on Pe sârmă

    /// The service macOS lists for images and text files in Finder and
    /// elsewhere. What you hang yourself is pinned, and the line comes down
    /// to show it. A text file is copied in as a note.
    @objc func hangOnLine(_ pasteboard: NSPasteboard, userData: String?,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        comeDown(on: nil)
        var any = false
        for url in urls {
            let hung = NoteFolder.isTextFile(url) ? NoteFolder.adopt(url) : url
            if let hung, line.hangKept(hung) { any = true }
        }
        if !any { NSSound.beep() }
    }

    // MARK: Keys over a photo

    /// Delete and Space while the pointer rests on a photo: Delete does what
    /// its corner button does, Space takes a quick look, as in Finder. Like
    /// ⌘Z, they are borrowed as hot keys only then, so every other app keeps
    /// them.
    private var photoKeys: [HotKey] = []
    private var photoKeysFor: UUID?

    private func holdPhotoKeys(over id: UUID?) {
        let id = id.flatMap { id in line.items.first { $0.id == id && !$0.falling && !$0.held }?.id }
        guard id != photoKeysFor else { return }
        photoKeysFor = id
        photoKeys = []
        guard let id else { return }
        photoKeys = [
            HotKey(Shortcut(keyCode: kVK_Delete, modifiers: [], key: "\u{8}")) { [weak self] in
                guard let line = self?.line else { return }
                let ids = line.selectedItems.map(\.id)
                if ids.isEmpty { line.pressCorner(id) } else { line.discard(ids) }
            },
            HotKey(Shortcut(keyCode: kVK_Space, modifiers: [], key: " ")) { [weak self] in
                self?.quickLookToggle(id)
            },
        ].compactMap { $0 }
    }

    /// Like Delete and undo, these belong to the line only while the
    /// pointer is over it. Selection never takes focus from another app.
    private var selectionKeys: [HotKey] = []
    private var selectionKeysHeld = false

    private func holdSelectionKeys(_ hold: Bool) {
        let hold = hold && !line.selectedIDs.isEmpty
        guard hold != selectionKeysHeld else { return }
        selectionKeysHeld = hold
        selectionKeys = []
        guard hold else { return }
        selectionKeys = [
            HotKey(Shortcut(keyCode: kVK_Escape, modifiers: [], key: "\u{1b}")) { [weak self] in
                self?.line.clearSelection()
            },
            HotKey(Shortcut(keyCode: kVK_ANSI_C, modifiers: [.command], key: "c")) { [weak self] in
                guard let line = self?.line else { return }
                line.copy(line.selectedItems.map(\.id))
            },
        ].compactMap { $0 }
    }

    /// The photo whose card is under the pointer, if any.
    private func photo(under mouse: NSPoint) -> UUID? {
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        return line.hitRects.first { $0.value.contains(flipped) }?.key
    }

    /// Space opens Quick Look, and closes it again if it is already open.
    private func quickLookToggle(_ id: UUID) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            line.quickLook(id)
        }
    }

    // MARK: Putting back

    /// ⌘Z while the pointer is on the line or where its menu just closed.
    /// The line never takes the keyboard, so it only borrows ⌘Z then as a
    /// hot key. Everywhere else
    /// ⌘Z stays the undo of the app you are in.
    private var putBackKey: HotKey?
    private var putBackMonitor: Any?
    private var undoAnchor: (point: NSPoint, application: pid_t?)?

    /// Key events delivered to Pe sârmă itself also need a route to undo,
    /// such as after a menu activates it. The global hot key covers other
    /// apps; this consumes only a local key in the same narrow undo scope.
    private func watchPutBackKey() {
        putBackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.putBackKey != nil,
                  !GrabView.isShowingMenu, !Share.shared.isOpen,
                  Int(event.keyCode) == Shortcut.putBack.keyCode,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else { return event }
            self.putBack()
            return nil
        }
    }

    private func keepUndoAtPointer() {
        guard isRevealed else { return }
        undoAnchor = (NSEvent.mouseLocation, NSWorkspace.shared.frontmostApplication?.processIdentifier)
        holdPutBackKey(true)
    }

    /// A context menu can end below the photo band. Keep that spot part of
    /// the undo interaction until the pointer moves, another app is chosen,
    /// or a new click starts something else. Other apps keep their own undo.
    private func isAtUndoAnchor(_ point: NSPoint) -> Bool {
        guard let anchor = undoAnchor else { return false }
        guard line.canPutBack,
              abs(point.x - anchor.point.x) <= 12, abs(point.y - anchor.point.y) <= 12,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == anchor.application else {
            releaseUndoAnchor()
            return false
        }
        return true
    }

    private func releaseUndoAnchor() {
        guard undoAnchor != nil else { return }
        undoAnchor = nil
        holdPutBackKey(false)
        itemsChanged()
    }

    /// Set when another app holds ⌘Z, so it is not asked for again on every
    /// tick, only the next time the pointer comes to the line.
    private var putBackKeyRefused = false

    private func holdPutBackKey(_ hold: Bool) {
        guard hold && line.canPutBack else {
            putBackKey = nil
            putBackKeyRefused = false
            return
        }
        guard putBackKey == nil, !putBackKeyRefused else { return }
        putBackKey = HotKey(Shortcut.putBack) { [weak self] in self?.putBack() }
        putBackKeyRefused = putBackKey == nil
    }

    /// From the menu the line is usually up, so it comes down for a moment
    /// to show the photos going back.
    private func putBack() {
        if !isRevealed {
            panel.placeOnScreen()
            updateCapacity()
            wanted = true
            refresh()
            reveal(peekFor: 2.5)
        }
        line.putBack()
    }

    // MARK: Shortcut

    private func registerShortcut() {
        hotKey = nil
        guard let shortcut = Shortcut.current else { return }
        hotKey = HotKey(shortcut) { [weak self] in self?.toggle() }
    }

    private func registerSearchShortcut() {
        searchHotKey = nil
        guard let shortcut = Shortcut.search else { return }
        searchHotKey = HotKey(shortcut) { [weak self] in self?.startSearch() }
    }

    private func changeShortcut() {
        record(\.current, register: registerShortcut, other: registerSearchShortcut,
               registered: { [weak self] in self?.hotKey != nil })
    }

    private func changeSearchShortcut() {
        record(\.search, register: registerSearchShortcut, other: registerShortcut,
               registered: { [weak self] in self?.searchHotKey != nil })
    }

    /// Both shortcuts are off while recording, so pressing either one
    /// records it instead of showing or searching the line.
    private func record(_ setting: ReferenceWritableKeyPath<Shortcut.Type, Shortcut?>,
                        register: @escaping () -> Void, other: @escaping () -> Void,
                        registered: @escaping () -> Bool) {
        hotKey = nil
        searchHotKey = nil
        ShortcutRecorder.shared.record { result in
            // The other one first, so taking its keys fails below.
            other()
            if let result {
                let previous = Shortcut.self[keyPath: setting]
                Shortcut.self[keyPath: setting] = result
                register()
                // Taken by another app, or by the other shortcut: keep the
                // one that worked.
                if result != nil && !registered() {
                    NSSound.beep()
                    Shortcut.self[keyPath: setting] = previous
                }
            }
            register()
        }
    }

    private func setKeep(_ n: Int?) {
        guard n != Line.keepOnLine else { return }
        Line.keepOnLine = n
        updateCapacity()
        line.trim()
    }

    private func setSize(_ size: Layout.Size) {
        guard size != Layout.size else { return }
        Layout.size = size
        panel.placeOnScreen(panel.screen)
        updateCapacity()
        line.reloadThumbnails()
    }

    private func updateCapacity() {
        let usable = panel.frame.width - 200
        let fits = max(3, min(12, Int(usable / Layout.spacing)))
        line.visibleCount = fits
        line.maxItems = max(fits, Line.keepOnLine ?? fits)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()
        let menu = NSMenu()
        // Items say themselves whether they can be used, like Take everything
        // down on an empty line.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The shirt fills in while copied images are hung, so it shows at a
    /// glance that the clipboard is being watched. It is dimmed while the
    /// line is empty, so resting in the menu bar and seeing nothing come down
    /// does not look broken.
    /// The wire, clip and photo symbol, drawn as a template so macOS tints it
    /// for light and dark menu bars. 18 pt, with a 2x file for Retina.
    private static let statusImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private func updateStatusIcon() {
        let on = ClipboardWatcher.isEnabled
        let count = line.liveCount
        let description = on ? L("Pe sârmă, hanging copied images") : "Pe sârmă"
        let state = count == 0 ? L("The line is empty") : String(format: L("%d on the line"), count)
        let image = Self.statusImage
        image?.accessibilityDescription = "\(description), \(state)"
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = count == 0
        statusItem.button?.toolTip = "\(description)\n\(state)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleItem = ClosureMenuItem(isRevealed ? L("Hide line") : L("Show line")) { [weak self] in
            self?.toggle()
        }
        if let shortcut = Shortcut.current, shortcut.key.count == 1 {
            toggleItem.keyEquivalent = shortcut.key
            toggleItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(toggleItem)

        let searchItem = ClosureMenuItem(L("Search the line")) { [weak self] in self?.startSearch() }
        if let shortcut = Shortcut.search, shortcut.key.count == 1 {
            searchItem.keyEquivalent = shortcut.key
            searchItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        searchItem.isEnabled = line.liveCount > 0
        menu.addItem(searchItem)

        let putBackItem = ClosureMenuItem(L("Put back"), key: "z") { [weak self] in
            self?.putBack()
        }
        putBackItem.isEnabled = line.canPutBack
        menu.addItem(putBackItem)

        let clearItem = ClosureMenuItem(L("Take everything down")) { [weak self] in
            self?.line.clear()
        }
        clearItem.isEnabled = line.liveCount > 0
        menu.addItem(clearItem)

        if !Held.heldIDs.isEmpty {
            menu.addItem(ClosureMenuItem(L("Hang everything back")) { Held.hangEverythingBack() })
        }

        // Where screenshots and other images come from, together.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Screenshots")))
        let inbox = ClosureMenuItem(L("Handle screenshots")) { [weak self] in
            self?.setInbox(!Inbox.isEnabled)
        }
        inbox.state = Inbox.isEnabled ? .on : .off
        inbox.toolTip = L("Screenshots hang instantly and skip the Desktop")
        menu.addItem(inbox)
        let copyItem = ClosureMenuItem(L("Copy each screenshot")) {
            AppDelegate.copiesScreenshots.toggle()
        }
        copyItem.state = Self.copiesScreenshots ? .on : .off
        copyItem.toolTip = L("Each new screenshot goes to the clipboard as it hangs")
        menu.addItem(copyItem)

        let folderItem = NSMenuItem(title: L("Also watch folders"), action: nil, keyEquivalent: "")
        let folderMenu = NSMenu()
        folderMenu.autoenablesItems = false
        let folders = Self.extraFolders
        // Each folder is ticked: a click stops watching it, as with any
        // ticked item. Holding Option turns it into Show in Finder.
        for folder in folders {
            let name = FileManager.default.displayName(atPath: folder.path)
            let item = ClosureMenuItem(name) { [weak self] in
                AppDelegate.extraFolders.removeAll { $0.standardizedFileURL == folder.standardizedFileURL }
                self?.startWatcher()
            }
            item.state = .on
            folderMenu.addItem(item)
            let reveal = ClosureMenuItem(String(format: L("Show “%@” in Finder"), name)) {
                NSWorkspace.shared.open(folder)
            }
            reveal.isAlternate = true
            reveal.keyEquivalentModifierMask = .option
            folderMenu.addItem(reveal)
        }
        if !folders.isEmpty { folderMenu.addItem(.separator()) }
        let add = ClosureMenuItem(L("Add Folder…")) { [weak self] in self?.chooseExtraFolder() }
        add.isEnabled = folders.count < Self.maxExtraFolders
        folderMenu.addItem(add)
        folderItem.submenu = folderMenu
        menu.addItem(folderItem)

        menu.addItem(ClosureMenuItem(L("Open screenshots folder")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.watcher.folder)
        })

        // What you copy, in a section of its own: each kind is its own choice.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Hang what you copy")))
        let kinds: [(String, String, ReferenceWritableKeyPath<ClipboardWatcher.Type, Bool>)] = [
            (L("Images"), L("Images you copy hang on the line too"), \.imagesEnabled),
            (L("Text"), L("Text you copy hangs on the line too"), \.textEnabled),
            (L("Links"), L("Links you copy hang on the line too"), \.linksEnabled),
        ]
        for (title, tip, key) in kinds {
            let item = ClosureMenuItem(title) { [weak self] in
                ClipboardWatcher.self[keyPath: key].toggle()
                self?.refreshClipboardWatcher()
            }
            item.state = ClipboardWatcher.self[keyPath: key] ? .on : .off
            item.toolTip = tip
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let bringDown = NSMenuItem(title: L("Bring the line down"), action: nil, keyEquivalent: "")
        let options = NSMenu()
        let hover = ClosureMenuItem(L("When the pointer rests in the menu bar")) {
            AppDelegate.opensFromMenuBar.toggle()
        }
        hover.state = Self.opensFromMenuBar ? .on : .off
        options.addItem(hover)
        let peek = ClosureMenuItem(L("When something new hangs")) {
            AppDelegate.peeksAtNew.toggle()
        }
        peek.state = Self.peeksAtNew ? .on : .off
        options.addItem(peek)
        let fullScreen = ClosureMenuItem(L("Over full screen apps")) { [weak self] in
            FullScreen.showLineOver.toggle()
            self?.refresh()
        }
        fullScreen.state = FullScreen.showLineOver ? .on : .off
        options.addItem(fullScreen)
        bringDown.submenu = options
        menu.addItem(bringDown)

        let keepItem = NSMenuItem(title: L("Keep on line"), action: nil, keyEquivalent: "")
        let keeps = NSMenu()
        let fit = ClosureMenuItem(L("As many as fit")) { [weak self] in self?.setKeep(nil) }
        fit.state = Line.keepOnLine == nil ? .on : .off
        keeps.addItem(fit)
        for n in Line.keepChoices {
            let item = ClosureMenuItem(String(format: L("%d photos"), n)) { [weak self] in self?.setKeep(n) }
            item.state = Line.keepOnLine == n ? .on : .off
            keeps.addItem(item)
        }
        keepItem.submenu = keeps
        menu.addItem(keepItem)

        let sizeItem = NSMenuItem(title: L("Size"), action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (size, title) in [(Layout.Size.small, L("Small")), (.medium, L("Medium")), (.large, L("Large"))] {
            let item = ClosureMenuItem(title) { [weak self] in self?.setSize(size) }
            item.state = Layout.size == size ? .on : .off
            sizes.addItem(item)
        }
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)

        let zoomItem = ClosureMenuItem(L("Zoom on hover")) { [weak self] in
            Zoom.isEnabled.toggle()
            if !Zoom.isEnabled { self?.zoom.hide() }
        }
        zoomItem.state = Zoom.isEnabled ? .on : .off
        menu.addItem(zoomItem)

        let shortcutItem = NSMenuItem(title: L("Shortcut"), action: nil, keyEquivalent: "")
        let shortcuts = NSMenu()
        // One for showing the line, one for searching it, each with its
        // own Change Shortcut….
        let shortcutKinds: [(String, Shortcut?, () -> Void)] = [
            (L("Show line"), Shortcut.current, { [weak self] in self?.changeShortcut() }),
            (L("Search the line"), Shortcut.search, { [weak self] in self?.changeSearchShortcut() }),
        ]
        for (i, kind) in shortcutKinds.enumerated() {
            if i > 0 { shortcuts.addItem(.separator()) }
            shortcuts.addItem(.sectionHeader(title: kind.0))
            let current = NSMenuItem(title: kind.1?.display ?? L("None"), action: nil, keyEquivalent: "")
            current.isEnabled = false
            shortcuts.addItem(current)
            shortcuts.addItem(ClosureMenuItem(L("Change Shortcut…"), handler: kind.2))
        }
        shortcutItem.submenu = shortcuts
        menu.addItem(shortcutItem)

        menu.addItem(.separator())

        let sound = ClosureMenuItem(L("Sounds")) { [weak self] in
            guard let self else { return }
            self.line.soundOn.toggle()
        }
        sound.state = line.soundOn ? .on : .off
        menu.addItem(sound)

        let login = ClosureMenuItem(L("Open at login")) {
            AppDelegate.toggleLaunchAtLogin()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(languageItem())

        // The only thing here that uses the network, and only when asked: it
        // reads the public update feed and shows the result in the app.
        menu.addItem(ClosureMenuItem(L("Check for Updates…")) { [weak self] in
            self?.checkForUpdates()
        })
        menu.addItem(ClosureMenuItem(L("About Pe sârmă")) {
            AppDelegate.showAbout()
        })
        let diagnostic = NSMenuItem(title: L("Diagnostic"), action: nil, keyEquivalent: "")
        let diagnosticMenu = NSMenu()
        diagnosticMenu.addItem(ClosureMenuItem(L("Open logs folder")) {
            try? FileManager.default.createDirectory(at: Diag.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Diag.folder)
        })
        diagnosticMenu.addItem(ClosureMenuItem(L("Export diagnostic…")) {
            AppDelegate.exportDiagnostic()
        })
        diagnosticMenu.addItem(ClosureMenuItem(L("Copy session ID")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Diag.sessionID, forType: .string)
            NSPasteboard.general.setData(Data(), forType: selfCopyType)
        })
        let detailed = ClosureMenuItem(L("Detailed log until quit")) {
            Diag.detailed.toggle()
            Diag.log(.info, "diag.detailed", ["on": "\(Diag.detailed)"])
        }
        detailed.state = Diag.detailed ? .on : .off
        diagnosticMenu.addItem(detailed)
        diagnostic.submenu = diagnosticMenu
        menu.addItem(diagnostic)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit Pe sârmă"), key: "q") {
            NSApp.terminate(nil)
        })
    }


    #if MENU_PROBE
    // Test builds only (compiled with -DMENU_PROBE, never shipped). The menu
    // bar item cannot be reached by accessibility on this macOS, so a test
    // asks the real menu object, built by the real menuNeedsUpdate, to write
    // its titles (SIGUSR1) or to run an item by its path (SIGUSR2, path read
    // from $PESARMA_PROBE_DIR/pick).
    private static var probeSources: [DispatchSourceSignal] = []

    private func installMenuProbe() {
        guard let dir = ProcessInfo.processInfo.environment["PESARMA_PROBE_DIR"] else { return }
        for sig in [SIGUSR1, SIGUSR2] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let menu = self.statusItem.menu else { return }
                    self.menuNeedsUpdate(menu)
                    if sig == SIGUSR1 {
                        func dump(_ m: NSMenu, _ depth: Int) -> String {
                            m.items.map { item in
                                let line = String(repeating: "  ", count: depth) + (item.isSeparatorItem ? "---" : item.title) + (item.state == .on ? " [x]" : "")
                                return line + "\n" + (item.submenu.map { dump($0, depth + 1) } ?? "")
                            }.joined()
                        }
                        try? dump(menu, 0).write(toFile: dir + "/menu.txt", atomically: true, encoding: .utf8)
                    } else if let path = try? String(contentsOfFile: dir + "/pick", encoding: .utf8) {
                        var current = menu
                        var target: NSMenuItem?
                        for part in path.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/") {
                            target = current.items.first { $0.title == String(part) }
                            if let sub = target?.submenu { current = sub }
                        }
                        if let target, let action = target.action { NSApp.sendAction(action, to: target.target, from: target) }
                    }
                }
            }
            src.resume()
            Self.probeSources.append(src)
        }
    }
    #endif

    // MARK: Language

    /// Language submenu: each language in its own name, a check on the current
    /// choice, and "System language" to go back to the automatic pick.
    private func languageItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("Language"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for choice in AppLanguage.choices {
            let entry = ClosureMenuItem(choice.name) { [weak self] in self?.setLanguage(choice.code) }
            entry.state = AppLanguage.chosen == choice.code ? .on : .off
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        let system = ClosureMenuItem(L("System language")) { [weak self] in self?.setLanguage(nil) }
        system.state = AppLanguage.chosen == nil ? .on : .off
        submenu.addItem(system)
        item.submenu = submenu
        return item
    }

    /// The menu and everything opened from now on use the new language at
    /// once; windows already open and system panels pick it up when the app is
    /// reopened, so the user is offered that, with settings restored on quit.
    private func setLanguage(_ code: String?) {
        guard code != AppLanguage.chosen else { return }
        AppLanguage.chosen = code
        Diag.log(.info, "language.change", ["to": code ?? "system", "active": AppLanguage.active])
        updateStatusIcon()
        let alert = NSAlert()
        alert.messageText = L("Language changed")
        alert.informativeText = L("The menu already uses the new language. Open windows and system dialogs follow after reopening Pe sârmă.")
        alert.addButton(withTitle: L("Reopen now"))
        alert.addButton(withTitle: L("Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { Self.relaunch() }
    }

    // MARK: Updates

    private var checkingForUpdates = false
    private var updateWindow: NSPanel?

    /// Asks the public feed and tells the user one of: this is the latest
    /// version, there is a newer one (with how to get it), or the check failed.
    private func checkForUpdates() {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let language = AppLanguage.active
        Task { @MainActor in
            let result = await Updates.check(current: current, language: language)
            checkingForUpdates = false
            switch result {
            case .upToDate(let cur, let published):
                Diag.log(.info, "update.check", ["result": "latest", "current": cur, "published": published])
                present(L("You have the latest version"),
                        L("Pe sârmă %@ is the newest published version.").replacingOccurrences(of: "%@", with: cur))
            case .newer(let offer):
                Diag.log(.info, "update.check", ["result": "newer", "current": current, "published": offer.version,
                                                 "install": Updates.installKind() == .homebrew ? "homebrew" : "direct"])
                offerUpdate(offer, current: current)
            case .unreachable(let why):
                Diag.log(.warning, "update.check", ["result": "unreachable", "why": why])
                failed(L("Pe sârmă could not reach the update server. Check your connection and try again."))
            case .invalidFeed(let field):
                Diag.log(.warning, "update.check", ["result": "invalid", "field": field])
                failed(L("The server answered, but the update information is not valid."))
            }
        }
    }

    @discardableResult
    private func present(_ title: String, _ text: String, accessory: NSView? = nil, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.accessoryView = accessory
        for b in buttons { alert.addButton(withTitle: b) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func failed(_ reason: String) {
        let r = present(L("Could not check for updates"), reason + "\n\n" + L("The rest of Pe sârmă keeps working as usual."),
                        accessory: nil, buttons: ["OK", L("Open the website")])
        if r == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.updatesURL) }
    }

    private func offerUpdate(_ offer: UpdateOffer, current: String) {
        let title = L("Pe sârmă %@ is available").replacingOccurrences(of: "%@", with: offer.version)
        let head = (offer.changes.isEmpty ? "" : offer.changes + "\n\n")
            + L("You have version %@.").replacingOccurrences(of: "%@", with: current)
        if Updates.installKind() == .homebrew {
            let field = NSTextField(string: Updates.brewCommand)
            field.isEditable = false
            field.isSelectable = true
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
            let r = present(title, head + "\n\n" + L("This copy was installed with Homebrew, so Homebrew updates it. Run in Terminal:"),
                            accessory: field, buttons: [L("Copy command"), L("Later")])
            if r == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Updates.brewCommand, forType: .string)
            }
        } else if Updates.canReplaceInPlace() {
            let r = present(title, head + "\n\n" + L("Update now downloads the new version, checks its signature, replaces this copy and reopens Pe sârmă. Your settings and language are kept."),
                            accessory: nil, buttons: [L("Update now"), L("Later")])
            if r == .alertFirstButtonReturn { runUpdate(offer) }
        } else {
            let r = present(title, head + "\n\n" + L("This copy is in a folder the app cannot change by itself. Download the new version and replace this one."),
                            accessory: nil, buttons: [L("Download the new version"), L("Later")])
            if r == .alertFirstButtonReturn { NSWorkspace.shared.open(offer.url) }
        }
    }

    private func runUpdate(_ offer: UpdateOffer) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Pe sârmă"
        let label = NSTextField(labelWithString: "")
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        let stack = NSStackView(views: [spinner, label])
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = stack
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateWindow = panel
        Task { @MainActor in
            do {
                let app = try await Updates.install(offer) { label.stringValue = $0 }
                Diag.log(.info, "update.install", ["to": offer.version, "result": "ok"])
                Updates.relaunchAfterExit(app)
                NSApp.terminate(nil)
            } catch {
                panel.orderOut(nil)
                updateWindow = nil
                Diag.log(.error, "update.install", ["to": offer.version, "result": "failed", "why": error.localizedDescription])
                present(L("The update could not be installed"),
                        error.localizedDescription + "\n\n" + L("The installed version was left unchanged."))
            }
        }
    }

    /// Starts a fresh copy once this one has quit. Quitting runs
    /// applicationWillTerminate, which puts the macOS capture settings back.
    private static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// gordas.dev/pe-sarma with the running version and the app's language,
    /// for when the check cannot be completed in the app.
    private static var updatesURL: URL {
        var components = URLComponents(string: "https://gordas.dev/pe-sarma/")!
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var query = [URLQueryItem(name: "update", value: version)]
        query.append(URLQueryItem(name: "lang", value: AppLanguage.active))
        components.queryItems = query
        return components.url!
    }

    /// The standard About panel, with the credit for this edition and the
    /// upstream attribution that the MIT notice asks to keep.
    private static func showAbout() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: 11)
        func add(_ text: String) {
            credits.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ]))
        }
        add(L("Pe sârmă — the Romanian edition, published and maintained by Cristi Gordaș.") + "\n\n")
        add(L("Based on Tendedero, created by Alejandro Buján. MIT license.") + "\n\n")
        add(L("Free and open source. No account, no network, no analytics.") + "\n")
        credits.append(NSAttributedString(string: "https://github.com/gordasgdc/pe-sarma", attributes: [
            .font: font, .link: URL(string: "https://github.com/gordasgdc/pe-sarma")!, .paragraphStyle: paragraph,
        ]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pe sârmă",
            .credits: credits,
        ])
    }

    /// Saves a ZIP of the local logs where the user chooses. Nothing is sent.
    private static func exportDiagnostic() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PeSarma-diagnostic-\(stamp).zip"
        panel.message = L("The package holds only local logs and technical settings. It is not sent anywhere.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Diag.export(to: url)
            Diag.log(.info, "diag.export", ["result": "ok"])
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Diag.log(.error, "diag.export", ["result": "failed", "code": "\((error as NSError).code)"])
            let alert = NSAlert()
            alert.messageText = L("Could not export the diagnostic")
            alert.runModal()
        }
    }

    private static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change the login setting")
            alert.informativeText = L("Move Pe sârmă to the Applications folder and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Quick Look

    /// With no window of ours in front, Quick Look finds its controller here.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLook.shared.take(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLook.shared.release(panel)
    }

}

