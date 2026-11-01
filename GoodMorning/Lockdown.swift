import AppKit

/// The soft lock, and the full-screen page, which come and go separately.
///
/// While locked, the Dock and menu bar are hidden, Cmd-Tab and Cmd-H do nothing, and switching to another app
/// or Space (with Mission Control, a swipe or Ctrl-arrow) brings the page straight back. Force Quit and Spotlight
/// still work, and quitting or crashing gives everything back, because these options only apply while this app
/// is frontmost.
///
/// Full screen fills the screen with the page, locked or not.
///
/// AppKit raises an exception for invalid option combinations, so only these two sets are used.
/// (Hiding the menu bar requires hiding the Dock; disabling process switching requires hiding
/// or auto-hiding the Dock.)
@MainActor
final class Lockdown {
    private static let strict: NSApplication.PresentationOptions =
        [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
    private static let relaxed: NSApplication.PresentationOptions =
        [.autoHideDock, .autoHideMenuBar]

    /// Apps that may come forward while locked: Force Quit and the login window, Spotlight, password prompts,
    /// and the open panel, which runs in a process of its own.
    private static let allowedApps = ["com.apple.loginwindow", "com.apple.Spotlight", "com.apple.SecurityAgent"]
    private static let allowedPrefixes = ["com.apple.appkit.xpc."]

    private(set) var isLocked = false
    private(set) var isFullScreen = false
    private weak var window: NSWindow?
    private var savedFrame: NSRect?
    private var savedStyle: NSWindow.StyleMask = []
    private var backdrop: NSWindow?
    private var watchers: [NSObjectProtocol] = []

    /// The Dock, menu bar and Cmd-Tab go, and the page stays in front. The window keeps its size.
    func lock(_ window: NSWindow) {
        self.window = window
        isLocked = true
        NSApp.activate()
        applyOptions()
        // Brought back on whichever Space you went to, rather than taking you back to its own.
        window.collectionBehavior.insert(.moveToActiveSpace)
        watchForLeaving()
    }

    /// Goal met, Esc, or ⌘L: the Dock, menu bar and Cmd-Tab come back. The window keeps its size.
    func unlock() {
        isLocked = false
        applyOptions()
        window?.collectionBehavior.remove(.moveToActiveSpace)
        let center = NSWorkspace.shared.notificationCenter
        watchers.forEach(center.removeObserver)
        watchers.removeAll()
    }

    /// Fill the screen with the page.
    func enterFullScreen(_ window: NSWindow) {
        guard !isFullScreen else { return }
        // Hide the menu bar first, so the window is allowed to cover the top of the screen.
        NSApp.presentationOptions = Self.strict
        savedFrame = window.frame
        savedStyle = window.styleMask
        window.styleMask.remove([.resizable, .miniaturizable, .closable])
        window.isMovable = false
        setTrafficLightsHidden(true, in: window)
        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(lockedFrame(on: screen), display: true)
            showBackdrop(behind: window, on: screen)
        }
        window.makeKeyAndOrderFront(nil)
        isFullScreen = true
        applyOptions()
    }

    /// Back to an ordinary window. Also one that opened screen-sized without full screen (the window keeps its last
    /// frame, so it does after a quit while full screen), which would otherwise look full screen with no way out.
    func leaveFullScreen(_ window: NSWindow) {
        if isFullScreen {
            isFullScreen = false
            applyOptions()
            window.styleMask = savedStyle
            window.isMovable = true
            setTrafficLightsHidden(false, in: window)
            hideBackdrop(from: window)
            window.setFrame(restoredFrame(for: window), display: true, animate: true)
        } else if isScreenSized(window.frame, for: window) {
            window.setFrame(restoredFrame(for: window), display: true, animate: true)
        }
    }

    /// Locked: everything off. Full screen but unlocked: the Dock and menu bar slide in when you reach for them.
    private func applyOptions() {
        NSApp.presentationOptions = isLocked ? Self.strict : isFullScreen ? Self.relaxed : []
    }

    /// Presentation options can't stop Mission Control or a swipe to another Space, so while locked, another app
    /// coming forward, or a change of Space, brings the page back.
    private func watchForLeaving() {
        guard watchers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        watchers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                           queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? ""
            MainActor.assumeIsolated {
                guard app != .current, !Self.allowedApps.contains(id),
                      !Self.allowedPrefixes.contains(where: id.hasPrefix) else { return }
                self?.comeBack()
            }
        })
        watchers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.comeBack() }
        })
    }

    private func comeBack() {
        guard isLocked, let window else { return }
        // A polite activate() can be turned down while another app is in front, and this one has to win.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The whole screen, less the strip beside the camera notch on MacBooks that have one. AppKit won't
    /// let a window up into that strip: it pushes the window down instead, and the bottom bar falls off the screen.
    private func lockedFrame(on screen: NSScreen) -> NSRect {
        var frame = screen.frame
        frame.size.height -= screen.safeAreaInsets.top
        return frame
    }

    /// Black behind the page, over the whole screen, the way native full screen does it: it fills the strip beside
    /// the notch, where the desktop would otherwise show above the page, and the window's rounded corners.
    /// A borderless window, unlike the page's, is allowed up into that strip.
    private func showBackdrop(behind window: NSWindow, on screen: NSScreen) {
        let backdrop = self.backdrop ?? NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.backgroundColor = .black
        backdrop.ignoresMouseEvents = true
        backdrop.setFrame(screen.frame, display: false)
        window.addChildWindow(backdrop, ordered: .below)
        self.backdrop = backdrop
    }

    private func hideBackdrop(from window: NSWindow) {
        guard let backdrop else { return }
        window.removeChildWindow(backdrop)
        backdrop.orderOut(nil)
    }

    private func setTrafficLightsHidden(_ hidden: Bool, in window: NSWindow) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// The frame from before full screen, unless that was already screen-sized
    /// (say, the app last quit while full screen). Then a comfortable centered window.
    private func restoredFrame(for window: NSWindow) -> NSRect {
        let visible = visibleFrame(for: window)
        if let saved = savedFrame, !isScreenSized(saved, for: window) {
            return saved
        }
        let size = NSSize(width: min(820, visible.width * 0.7), height: min(900, visible.height * 0.85))
        return NSRect(x: visible.midX - size.width / 2,
                      y: visible.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private func isScreenSized(_ frame: NSRect, for window: NSWindow) -> Bool {
        let visible = visibleFrame(for: window)
        return frame.width >= visible.width - 40 && frame.height >= visible.height - 40
    }

    private func visibleFrame(for window: NSWindow) -> NSRect {
        (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
