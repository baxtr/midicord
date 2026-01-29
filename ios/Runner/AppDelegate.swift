import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set up method channel for native file sharing
    let controller = window?.rootViewController as! FlutterViewController
    let shareChannel = FlutterMethodChannel(name: "com.midicord/share",
                                            binaryMessenger: controller.binaryMessenger)

    shareChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "shareFile" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path required", details: nil))
          return
        }
        self?.shareFile(at: filePath, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func shareFile(at path: String, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)

    // Verify file exists
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File does not exist", details: nil))
      return
    }

    DispatchQueue.main.async {
      let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

      // For iPad
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = self.window?.rootViewController?.view
        popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }

      activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
        if let error = error {
          result(FlutterError(code: "SHARE_ERROR", message: error.localizedDescription, details: nil))
        } else {
          result(completed)
        }
      }

      self.window?.rootViewController?.present(activityVC, animated: true, completion: nil)
    }
  }
}
