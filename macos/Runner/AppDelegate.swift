import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var uriChannel: FlutterMethodChannel?
  private var pendingUris: [String] = []
  private var dartUriHandlerReady = false

  /// Brand-aware channel prefix — reads CFBundleIdentifier at runtime.
  private lazy var channelPrefix: String = {
    Bundle.main.bundleIdentifier ?? "com.svid.app"
  }()

  /// Brand-aware URL scheme — reads from Info.plist CFBundleURLSchemes.
  private lazy var urlScheme: String = {
    if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]],
       let schemes = urlTypes.first?["CFBundleURLSchemes"] as? [String],
       let scheme = schemes.first {
      return scheme
    }
    return "svid"
  }()

  /// Brand display name — reads from Info.plist.
  private lazy var displayName: String = {
    Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
      ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
      ?? "Svid"
  }()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Set system-aware background (adapts to light/dark mode) as fallback
    // in case the window briefly becomes visible before Flutter renders.
    mainFlutterWindow?.backgroundColor = NSColor.windowBackgroundColor

    super.applicationDidFinishLaunching(notification)

    // CRITICAL FIX (v3): FlutterAppDelegate.super may have made the window
    // visible, but Flutter hasn't painted its first frame yet — the user
    // would see a black/transparent rectangle. Hide the window now;
    // WindowService.showAfterFirstFrame() will re-show it once the first
    // frame is on-screen.
    mainFlutterWindow?.orderOut(nil)

    if let flutterVC = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let messenger = flutterVC.engine.binaryMessenger

      // Wire up the MethodChannel for URI scheme routing (brand-aware).
      // This channel is native→Dart (AppDelegate invokes handleUri when
      // macOS delivers a URL); it keeps a persisted reference here so
      // application(_:open:) can reach Dart. The Dart side re-registers
      // its handler on hot restart, and the messenger survives the reset.
      uriChannel = FlutterMethodChannel(name: "\(channelPrefix)/uri_scheme",
                                        binaryMessenger: messenger)
      uriChannel?.setMethodCallHandler { [weak self] call, result in
        guard call.method == "uriHandlerReady" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.dartUriHandlerReady = true
        self?.flushPendingUris()
        result(nil)
      }

      // macos_actions and notification_permission channels are registered
      // via FlutterPlugin classes in MainFlutterWindow.swift so they
      // survive hot restart.
    }
  }

  // MARK: - macOS Services ("Download with {Brand}")

  /// Called by the macOS Services subsystem when the user selects
  /// "Download with {Brand}" from the Services menu in any application.
  /// The pasteboard contains either a public.url or public.plain-text item.
  @objc func downloadURL(_ pboard: NSPasteboard,
                          userData: String?,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    // Extract URL string from pasteboard (prefer URL type, fall back to plain text)
    let urlString: String?
    if let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL],
       let first = urls.first {
      urlString = first.absoluteString
    } else {
      urlString = pboard.string(forType: .string)
    }

    guard let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawURL.isEmpty else { return }

    // Percent-encode so the URL survives the deep link query parameter
    let encoded = rawURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawURL
    let deepLink = "\(urlScheme)://download?url=\(encoded)"

    // Bring the app window to front, then route to Flutter
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    routeUri(deepLink)
  }

  // MARK: - URL scheme ({brand}://)

  /// Called by macOS when the app is opened via the brand's URL scheme.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let urlString = url.absoluteString
      routeUri(urlString)
    }
  }

  private func routeUri(_ uri: String) {
    guard dartUriHandlerReady, let channel = uriChannel else {
      pendingUris.append(uri)
      return
    }
    channel.invokeMethod("handleUri", arguments: uri)
  }

  private func flushPendingUris() {
    guard dartUriHandlerReady, let channel = uriChannel else { return }
    let queued = pendingUris
    pendingUris.removeAll()
    for uri in queued {
      channel.invokeMethod("handleUri", arguments: uri)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Standard macOS behavior: app stays running when window closed
    // User can quit via Cmd+Q or menu
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
