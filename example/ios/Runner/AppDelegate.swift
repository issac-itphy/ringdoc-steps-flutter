import Flutter
import UIKit
import rdc_health

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 관찰 쿼리는 앱이 백그라운드로 실행될 때도 가장 먼저 다시 걸어야 함(Apple 문서)
    RdcHealthPlugin.registerObserverIfEnabled()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
