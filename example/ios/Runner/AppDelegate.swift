import Flutter
import UIKit
import rdc_health

// 결정: 본 앱(ios/Runner/AppDelegate.swift)처럼 didFinishLaunching에서 플러그인 등록. 백그라운드 실행 동작을 본 앱과 같게 재기 위함
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 관찰 쿼리는 앱이 백그라운드로 실행될 때도 가장 먼저 다시 걸어야 함(Apple 문서)
    HealthSpikeObserver.bootstrap()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
