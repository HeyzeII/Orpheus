import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1280, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 950, height: 650)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Window transparency, background movement, and glassmorphic vibrancy support
    self.isOpaque = false
    self.backgroundColor = .clear
    self.isMovableByWindowBackground = true

    // Add frosted glass visual effect view behind Flutter content
    let visualEffectView = NSVisualEffectView(frame: self.contentView?.bounds ?? .zero)
    visualEffectView.autoresizingMask = [.width, .height]
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.material = .underWindowBackground
    visualEffectView.state = .active
    self.contentView?.addSubview(visualEffectView, positioned: .below, relativeTo: flutterViewController.view)

    super.awakeFromNib()
  }
}
