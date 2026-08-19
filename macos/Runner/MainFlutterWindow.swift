import Cocoa
import ApplicationServices
import FlutterMacOS

public class MacOSWindowService: NSObject {
  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var monitorTimer: Timer?
  private var workspaceObserver: NSObjectProtocol?

  private var isStrutActive = false
  private var attachTop = true
  private var displayX: CGFloat = 0
  private var displayY: CGFloat = 0
  private var displayWidth: CGFloat = 1920
  private var displayHeight: CGFloat = 1080
  private var barHeight: CGFloat = 50

  public init(window: NSWindow, binaryMessenger: FlutterBinaryMessenger) {
    self.window = window
    super.init()

    let channel = FlutterMethodChannel(
      name: "com.example.task_monitor/macos_window",
      binaryMessenger: binaryMessenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handle(call, result: result)
    }

    setupWorkspaceObservers()
  }

  deinit {
    stopMonitoring()
    if let observer = workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  private func setupWorkspaceObservers() {
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: OperationQueue.main
    ) { [weak self] _ in
      self?.clampActiveWindowIfNeeded()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setAlwaysOnTop":
      guard let args = call.arguments as? [String: Any],
            let isAlwaysOnTop = args["isAlwaysOnTop"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGS", message: "isAlwaysOnTop required", details: nil))
        return
      }
      applyAlwaysOnTop(isAlwaysOnTop)
      result(true)

    case "reserveStrut":
      guard let args = call.arguments as? [String: Any],
            let attachTop = args["attachTop"] as? Bool,
            let barHeight = args["barHeight"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "attachTop and barHeight required", details: nil))
        return
      }
      self.attachTop = attachTop
      self.barHeight = CGFloat(barHeight)
      self.displayX = CGFloat(args["displayX"] as? Double ?? 0)
      self.displayY = CGFloat(args["displayY"] as? Double ?? 0)
      self.displayWidth = CGFloat(args["displayWidth"] as? Double ?? 1920)
      self.displayHeight = CGFloat(args["displayHeight"] as? Double ?? 1080)
      self.isStrutActive = true

      // Ensure window level & spaces behavior are set
      applyAlwaysOnTop(true)

      startMonitoring()
      clampActiveWindowIfNeeded()
      result(true)

    case "clearStrut":
      self.isStrutActive = false
      stopMonitoring()
      result(true)

    case "checkAccessibilityPermission":
      result(AXIsProcessTrusted())

    case "requestAccessibilityPermission":
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      let trusted = AXIsProcessTrustedWithOptions(options)
      result(trusted)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func applyAlwaysOnTop(_ isAlwaysOnTop: Bool) {
    guard let window = self.window else { return }

    if isAlwaysOnTop {
      // Use statusBar level to stay permanently above normal, floating, and zoomed windows
      window.level = .statusBar
      window.collectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle
      ]
    } else {
      window.level = .normal
      window.collectionBehavior = []
    }
  }

  private func startMonitoring() {
    stopMonitoring()
    monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.clampActiveWindowIfNeeded()
    }
  }

  private func stopMonitoring() {
    monitorTimer?.invalidate()
    monitorTimer = nil
  }

  private func clampActiveWindowIfNeeded() {
    guard isStrutActive, AXIsProcessTrusted() else { return }
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    var focusedWindowValue: AnyObject?
    let copyResult = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    )

    guard copyResult == .success, let focusedWindow = focusedWindowValue else { return }
    let windowElement = focusedWindow as! AXUIElement

    // Check if the window is minimized or hidden
    var minimizedValue: AnyObject?
    if AXUIElementCopyAttributeValue(windowElement, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
       let isMinimized = minimizedValue as? Bool, isMinimized {
      return
    }

    var posValue: AnyObject?
    var sizeValue: AnyObject?
    guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posValue) == .success,
          AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success else {
      return
    }

    var currentPos = CGPoint.zero
    var currentSize = CGSize.zero
    AXValueGetValue(posValue as! AXValue, .cgPoint, &currentPos)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &currentSize)

    // Check if the active window is roughly maximized or overlaps the bar region
    let windowRight = currentPos.x + currentSize.width
    let displayRight = displayX + displayWidth

    // Check horizontal overlap with current display
    let hasHorizontalOverlap = (currentPos.x < displayRight) && (windowRight > displayX)
    guard hasHorizontalOverlap else { return }

    var needsUpdate = false
    var targetPos = currentPos
    var targetSize = currentSize

    if attachTop {
      let reservedTop = displayY + barHeight
      // If the window's top is overlapping the top bar area (i.e. starts above reservedTop and goes below it)
      if currentPos.y < reservedTop && (currentPos.y + currentSize.height) > reservedTop {
        // If it's effectively maximized or touching the top screen boundary
        if currentPos.y <= displayY + 5 {
          let delta = reservedTop - currentPos.y
          targetPos.y = reservedTop
          targetSize.height = max(100, currentSize.height - delta)
          needsUpdate = true
        }
      }
    } else {
      let reservedBottom = displayY + displayHeight - barHeight
      let windowBottom = currentPos.y + currentSize.height
      // If the window's bottom extends into the bottom bar area
      if windowBottom > reservedBottom && currentPos.y < reservedBottom {
        if windowBottom >= (displayY + displayHeight - 5) {
          targetSize.height = max(100, reservedBottom - currentPos.y)
          needsUpdate = true
        }
      }
    }

    if needsUpdate {
      if targetPos != currentPos {
        if let newPosVal = AXValueCreate(.cgPoint, &targetPos) {
          AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, newPosVal)
        }
      }
      if targetSize != currentSize {
        if let newSizeVal = AXValueCreate(.cgSize, &targetSize) {
          AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, newSizeVal)
        }
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  private var windowService: MacOSWindowService?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.windowService = MacOSWindowService(
      window: self,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
