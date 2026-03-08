import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "verint_alarm/ios_alarm",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "prepareAlarmAudioSession":
          do {
            try Self.prepareAlarmAudioSession()
            result(true)
          } catch {
            result(
              FlutterError(
                code: "ios_alarm_audio_session_error",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func prepareAlarmAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.duckOthers])
    try session.setActive(true, options: [])
  }
}
