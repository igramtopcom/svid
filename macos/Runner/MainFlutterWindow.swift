import Cocoa
import FlutterMacOS
import UserNotifications
import WebKit
import desktop_multi_window
import window_manager

// MARK: - Cookie Plugin for HttpOnly Cookie Extraction
/// Native plugin to extract ALL cookies (including HttpOnly) from WKWebView
/// This is necessary because JavaScript's document.cookie cannot access HttpOnly cookies
/// which are commonly used for authentication (SID, HSID, sessionid, etc.)
class CookiePlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channelName = "\(Bundle.main.bundleIdentifier ?? "com.svid.app")/native_cookies"
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = CookiePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAllCookies":
            getAllCookies(call: call, result: result)
        case "getCookiesForDomain":
            getCookiesForDomain(call: call, result: result)
        case "clearCookies":
            clearCookies(call: call, result: result)
        case "debugGetAllCookies":
            debugGetAllCookies(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Debug: Get ALL cookies from ALL sources (WKWebsiteDataStore + HTTPCookieStorage)
    private func debugGetAllCookies(call: FlutterMethodCall, result: @escaping FlutterResult) {
        var allCookies: [[String: Any?]] = []

        // Source 1: WKWebsiteDataStore.default()
        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { wkCookies in
            print("[CookiePlugin] WKWebsiteDataStore has \(wkCookies.count) cookies")
            for cookie in wkCookies {
                var dict = self.cookieToDictionary(cookie)
                dict["source"] = "WKWebsiteDataStore"
                allCookies.append(dict)
            }

            // Source 2: HTTPCookieStorage.shared
            if let httpCookies = HTTPCookieStorage.shared.cookies {
                print("[CookiePlugin] HTTPCookieStorage has \(httpCookies.count) cookies")
                for cookie in httpCookies {
                    var dict = self.cookieToDictionary(cookie)
                    dict["source"] = "HTTPCookieStorage"
                    allCookies.append(dict)
                }
            }

            // Log summary by domain
            var domainCounts: [String: Int] = [:]
            for cookie in allCookies {
                if let domain = cookie["domain"] as? String {
                    domainCounts[domain, default: 0] += 1
                }
            }
            print("[CookiePlugin] Cookies by domain: \(domainCounts)")

            result(allCookies)
        }
    }

    /// Get ALL cookies from the default WKWebView data store
    /// This includes HttpOnly cookies that JavaScript cannot access
    private func getAllCookies(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { cookies in
            let cookieList = cookies.map { self.cookieToDictionary($0) }
            result(cookieList)
        }
    }

    /// Get cookies for a specific domain
    private func getCookiesForDomain(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let domain = args["domain"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing 'domain' argument",
                details: nil
            ))
            return
        }

        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { cookies in
            // Filter cookies by domain (including subdomains)
            let filteredCookies = cookies.filter { cookie in
                let cookieDomain = cookie.domain.lowercased()
                let targetDomain = domain.lowercased()

                // Match exact domain or subdomain
                return cookieDomain == targetDomain ||
                       cookieDomain.hasSuffix(".\(targetDomain)") ||
                       targetDomain.hasSuffix(cookieDomain)
            }

            let cookieList = filteredCookies.map { self.cookieToDictionary($0) }
            result(cookieList)
        }
    }

    /// Clear all cookies from the data store
    private func clearCookies(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let dataStore = WKWebsiteDataStore.default()
        let types: Set<String> = [WKWebsiteDataTypeCookies]

        dataStore.fetchDataRecords(ofTypes: types) { records in
            dataStore.removeData(ofTypes: types, for: records) {
                result(true)
            }
        }
    }

    /// Convert HTTPCookie to Dictionary for Flutter
    private func cookieToDictionary(_ cookie: HTTPCookie) -> [String: Any?] {
        return [
            "name": cookie.name,
            "value": cookie.value,
            "domain": cookie.domain,
            "path": cookie.path,
            "expiresDate": cookie.expiresDate?.timeIntervalSince1970,
            "isSecure": cookie.isSecure,
            "isHttpOnly": cookie.isHTTPOnly,
            "isSessionOnly": cookie.isSessionOnly,
            "sameSitePolicy": cookie.sameSitePolicy?.rawValue,
        ]
    }
}

// MARK: - macOS Actions Plugin
/// Dart→native bridge for macOS-specific actions (share sheet, etc.).
///
/// Registered via the FlutterPlugin registrar so the handler survives
/// hot restart, unlike the old AppDelegate direct-messenger registration.
class MacOSActionsPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channelName = "\(Bundle.main.bundleIdentifier ?? "com.svid.app")/macos_actions"
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
        let instance = MacOSActionsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "shareFile":
            guard let filePath = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "shareFile expects a String path",
                                    details: nil))
                return
            }
            showShareSheet(for: filePath, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func showShareSheet(for filePath: String, result: @escaping FlutterResult) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(code: "FILE_NOT_FOUND",
                                message: "File does not exist: \(filePath)",
                                details: nil))
            return
        }
        DispatchQueue.main.async {
            guard let contentView = NSApp.mainWindow?.contentView
                ?? NSApp.windows.first(where: { $0.contentViewController is FlutterViewController })?.contentView
            else {
                result(FlutterError(code: "NO_WINDOW",
                                    message: "No content view available",
                                    details: nil))
                return
            }
            let picker = NSSharingServicePicker(items: [fileURL])
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            result(nil)
        }
    }
}

// MARK: - Notification Permission Plugin
/// Handles UNUserNotificationCenter interaction via a Flutter MethodChannel.
///
/// Registered through the FlutterPlugin registrar (same as CookiePlugin) so
/// the channel handler is (re-)attached every time Flutter materialises the
/// plugin registry — crucially, this survives hot restart. The previous
/// incarnation wired the channel directly on engine.binaryMessenger inside
/// AppDelegate.applicationDidFinishLaunching, which runs only once per
/// process and left a stale handler after hot restart, producing
/// MissingPluginException on every requestPermission/checkPermission call.
class NotificationPermissionPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channelName = "\(Bundle.main.bundleIdentifier ?? "com.svid.app")/notification_permission"
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
        let instance = NotificationPermissionPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .authorized: result("granted")
                    case .denied: result("denied")
                    case .notDetermined: result("not_determined")
                    case .provisional: result("granted")
                    case .ephemeral: result("granted")
                    @unknown default: result("not_determined")
                    }
                }
            }
        case "requestPermission":
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            ) { granted, _ in
                DispatchQueue.main.async { result(granted) }
            }
        case "openSettings":
            if let bundleId = Bundle.main.bundleIdentifier,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleId)") {
                NSWorkspace.shared.open(url)
            } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(fallback)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}


// MARK: - Clipboard Monitor Plugin (v2.1 floating capture feature)
/// Native macOS clipboard monitor using NSPasteboard.changeCount polling.
///
/// Apple does NOT expose a clipboard-changed notification — the standard
/// pattern is to poll `NSPasteboard.general.changeCount` periodically and
/// detect change. Per spec v2.1 §3.1 + §6.2 implementation notes.
///
/// Channels:
/// - Method: svid.clipboard_monitor/methods (start/stop/readText)
/// - Event:  svid.clipboard_monitor/events (clipboard text changes)
class ClipboardMonitorPlugin: NSObject, FlutterPlugin {

    private var eventSink: FlutterEventSink?
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "svid.clipboard_monitor/methods",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "svid.clipboard_monitor/events",
            binaryMessenger: registrar.messenger
        )
        let instance = ClipboardMonitorPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startMonitoring(call.arguments as? [String: Any])
            result(true)
        case "stop":
            stopMonitoring()
            result(true)
        case "readText":
            result(NSPasteboard.general.string(forType: .string))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startMonitoring(_ args: [String: Any]?) {
        let intervalMs = (args?["intervalMs"] as? Int) ?? 500
        let interval = TimeInterval(intervalMs) / 1000.0

        // Capture baseline change count — Dart `ClipboardMonitorService`
        // is responsible for "ignore pre-existing content" (per spec §5.3).
        // We just emit raw changes from this point forward.
        lastChangeCount = NSPasteboard.general.changeCount

        timer?.invalidate()
        // Use .common mode so the timer keeps firing during scrolling, modal
        // sheets, and menu tracking. Default mode pauses the timer in those
        // states — bad UX for clipboard polling (user copies via context menu
        // → no event until menu closes).
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Poll NSPasteboard.changeCount + emit event on change.
    /// Skips non-text clipboards (image, file, etc.) per spec §11 E20.
    private func checkClipboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        if current == lastChangeCount { return }
        lastChangeCount = current

        // Only emit text content. Image/file clipboards return nil here.
        if let text = pb.string(forType: .string), !text.isEmpty {
            eventSink?(text)
        }
    }
}

// MARK: - FlutterStreamHandler (event channel)
extension ClipboardMonitorPlugin: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        // Codex audit P2 fix: cancellation of the event-channel
        // subscription must also stop polling. Without this, a Dart-side
        // stream cancel or engine teardown leaves NSPasteboard polling
        // running for the lifetime of the host process, with no sink to
        // deliver the events. Stop() is idempotent — explicit Dart-side
        // `stop()` already cleared the timer.
        stopMonitoring()
        return nil
    }
}

// MARK: - Floating Capture Panel Plugin (v2.1, Phase 1C.1)
/// Configures the spawned popup window to behave like a floating panel:
///   - Always on top of normal application windows (level=.statusBar)
///   - Visible across all macOS Spaces and stationary on Space switch
///   - Stays visible when the host app loses focus (hidesOnDeactivate=false)
///
/// Registered ONLY on child engines (popups), NOT on the main window — the
/// main app's window should keep normal behaviour.
///
/// Channel: svid.floating_capture.native (popup ↔ this plugin only).
/// Method:  `configurePanel` — apply the attributes; idempotent. Returns
///          `true` on success, FlutterError on a missing window reference
///          (rare — would mean the engine isn't attached yet).
///
/// NOT covered (deferred — needs NSPanel subclass / styleMask conversion):
/// click-on-popup focus-steal prevention. The status-bar level above
/// already addresses the more common "popup pops up while user is typing"
/// concern because show() doesn't makeKeyAndOrderFront.
class FloatingCapturePanelPlugin: NSObject, FlutterPlugin {
    private let registrar: FlutterPluginRegistrar

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "svid.floating_capture.native",
            binaryMessenger: registrar.messenger
        )
        let instance = FloatingCapturePanelPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configurePanel":
            configurePanel(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func configurePanel(result: @escaping FlutterResult) {
        // Bounce to main thread — NSWindow APIs require it. The Flutter
        // platform thread is the main thread on macOS, but we defer with
        // async to give the window time to attach if this fires too early
        // in the popup's startup sequence.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let window = self.registrar.view?.window else {
                result(FlutterError(
                    code: "NO_WINDOW",
                    message: "Popup window not attached yet",
                    details: nil
                ))
                return
            }
            // Always-on-top above normal windows. .statusBar is high enough
            // to float over fullscreen-but-not-true-fullscreen apps too.
            window.level = .statusBar
            // Visible on all Spaces, stationary when user switches Space.
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
            ]
            // Don't auto-hide when the host app loses focus — the popup
            // is supposed to stay visible while the user moves to a
            // browser to copy more URLs.
            window.hidesOnDeactivate = false
            // Floating capture renders its own rounded card. Keep the host
            // window transparent and clipped so brand dark surfaces do not
            // reveal a square canvas around the rounded popup corners.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 16
            window.contentView?.layer?.masksToBounds = true
            result(true)
        }
    }
}


// MARK: - Main Flutter Window
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Configure title bar natively to avoid force-unwrap crash in
    // window_manager's setTitleBarStyle() during hot restart.
    // WindowManager.swift:392 force-unwraps button superview which is nil on hot restart.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    // Register generated plugins
    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register native cookie plugin for HttpOnly cookie extraction
    CookiePlugin.register(with: flutterViewController.registrar(forPlugin: "CookiePlugin"))

    // Register notification permission plugin (survives hot restart, unlike
    // the previous binaryMessenger-direct registration in AppDelegate).
    NotificationPermissionPlugin.register(
        with: flutterViewController.registrar(forPlugin: "NotificationPermissionPlugin")
    )

    // Register macOS actions plugin (share sheet, etc.) — same reason.
    MacOSActionsPlugin.register(
        with: flutterViewController.registrar(forPlugin: "MacOSActionsPlugin")
    )

    // Register native clipboard monitor for v2.1 floating capture feature.
    // Polls NSPasteboard.changeCount @ 500ms (Apple has no clipboard
    // notification API). See lib/features/floating_capture/.
    ClipboardMonitorPlugin.register(
        with: flutterViewController.registrar(forPlugin: "ClipboardMonitorPlugin")
    )

    // v2.1 floating capture: register all generated plugins for child
    // windows spawned by `desktop_multi_window`. Without this, the popup
    // engine has no plugins (no MethodChannel access, no window_manager,
    // etc.) and the popup's main() will fail. Per plugin README §macOS.
    //
    // Phase 1C.1: also register FloatingCapturePanelPlugin so the popup
    // engine can self-configure as a floating panel (always-on-top,
    // visible across Spaces). This plugin is intentionally NOT on the
    // main window — only popups become panels.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      FloatingCapturePanelPlugin.register(
          with: controller.registrar(forPlugin: "FloatingCapturePanelPlugin")
      )
    }

    super.awakeFromNib()

    // CRITICAL FIX (v3): Hide window immediately after XIB creation.
    // The window must remain hidden until Flutter paints its first frame.
    // Without this, the user sees a black/transparent rectangle because
    // Flutter content isn't ready yet. WindowService.showAfterFirstFrame()
    // will call makeKeyAndOrderFront once the widget tree has been painted.
    self.orderOut(nil)
  }

  // Hide window on first launch to enable hot restart detection via isVisible().
  // First launch: window hidden → isVisible() returns false → Dart configures & shows
  // Hot restart: window already visible → isVisible() returns true → Dart skips unsafe calls
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
