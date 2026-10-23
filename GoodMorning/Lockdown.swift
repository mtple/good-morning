import AppKit

/// The soft lock. While engaged, the window fills the screen, the Dock and menu bar are hidden,
/// and Cmd-Tab and Cmd-H do nothing. Force Quit, Mission Control and Spotlight still work,
/// and quitting or crashing gives everything back, because these options only apply while
/// this app is frontmost.
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

    private(set) var isFullScreen = false
    private var savedFrame: NSRect?
    private var savedStyle: NSWindow.StyleMask = []

    /// Fill the screen and lock.
    func engage(_ window: NSWindow) {
        NSApp.activate()
        // Hide the menu bar first, so the window is allowed to cover the top of the screen.
        NSApp.presentationOptions = Self.strict
        guard !isFullScreen else { return }

        savedFrame = window.frame
        savedStyle = window.styleMask
        window.styleMask.remove([.resizable, .miniaturizable, .closable])
        window.isMovable = false
        setTrafficLightsHidden(true, in: window)
        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(lockedFrame(on: screen), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        isFullScreen = true
    }

    /// Goal met: keep the full-screen page, but give back the Dock, the menu bar and Cmd-Tab.
    func relax() {
        guard isFullScreen else { return }
        NSApp.presentationOptions = Self.relaxed
    }

    /// Back to an ordinary window.
    func release(_ window: NSWindow) {
        NSApp.presentationOptions = []
        guard isFullScreen else { return }
        window.styleMask = savedStyle
        window.isMovable = true
        setTrafficLightsHidden(false, in: window)
        window.setFrame(restoredFrame(for: window), display: true, animate: true)
        isFullScreen = false
    }

    /// The whole screen, less the strip beside the camera notch on MacBooks that have one. AppKit won't
    /// let a window up into that strip: it pushes the window down instead, and the bottom bar falls off the screen.
    private func lockedFrame(on screen: NSScreen) -> NSRect {
        var frame = screen.frame
        frame.size.height -= screen.safeAreaInsets.top
        return frame
    }

    private func setTrafficLightsHidden(_ hidden: Bool, in window: NSWindow) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// The frame from before the lock, unless that was already screen-sized
    /// (say, the app last quit while locked). Then a comfortable centered window.
    private func restoredFrame(for window: NSWindow) -> NSRect {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = savedFrame,
           saved.width < visible.width - 40 || saved.height < visible.height - 40 {
            return saved
        }
        let size = NSSize(width: min(820, visible.width * 0.7), height: min(900, visible.height * 0.85))
        return NSRect(x: visible.midX - size.width / 2,
                      y: visible.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }
}
