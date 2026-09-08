import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let minimumWindowSize = NSSize(width: 900, height: 600)
  private static let defaultWindowSize = NSSize(width: 1440, height: 900)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.minSize = Self.minimumWindowSize
    self.setContentSize(Self.defaultWindowSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
