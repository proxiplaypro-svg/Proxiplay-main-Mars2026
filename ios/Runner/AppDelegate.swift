import UIKit
import Flutter
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let mediaChannel = FlutterMethodChannel(
      name: "proxiplay/media",
      binaryMessenger: controller.binaryMessenger
    )
    mediaChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveImageToGallery" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "invalid_args", message: "Missing image bytes.", details: nil))
        return
      }
      self?.saveImageToGallery(bytes.data, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func saveImageToGallery(_ data: Data, result: @escaping FlutterResult) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    switch status {
    case .authorized, .limited:
      self.performSave(data, result: result)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
        DispatchQueue.main.async {
          if newStatus == .authorized || newStatus == .limited {
            self.performSave(data, result: result)
          } else {
            result(FlutterError(code: "permission_denied", message: "Photo library access denied.", details: nil))
          }
        }
      }
    default:
      result(FlutterError(code: "permission_denied", message: "Photo library access denied.", details: nil))
    }
  }

  private func performSave(_ data: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: data) else {
      result(FlutterError(code: "invalid_image", message: "Could not decode image data.", details: nil))
      return
    }
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAsset(from: image)
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result("saved")
        } else {
          result(FlutterError(code: "save_failed", message: error?.localizedDescription ?? "Unknown error.", details: nil))
        }
      }
    }
  }
}
