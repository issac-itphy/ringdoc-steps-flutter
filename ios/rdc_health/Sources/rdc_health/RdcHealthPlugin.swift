import Flutter
import HealthKit
import UIKit

public class RdcHealthPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "rdc_health", binaryMessenger: registrar.messenger())
    let instance = RdcHealthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    HealthSpikeObserver.onSamples = { samples in
      channel.invokeMethod("onStepSamples", arguments: ["samples": samples])
    }
    HealthSpikeLog.append(event: "plugin_registered")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let reader = HealthStepReader.shared
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "requestHealthKitAuthorization":
      reader.requestAuthorization { Self.reply(result, $0) }
    case "healthStepSamples":
      guard let args = call.arguments as? [String: Any],
            let from = args["from"] as? Int,
            let to = args["to"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "from, to(ms)가 필요합니다", details: nil))
        return
      }
      reader.samples(from: Self.date(from), to: Self.date(to)) { Self.reply(result, $0) }
    case "healthStepBuckets":
      guard let args = call.arguments as? [String: Any],
            let from = args["from"] as? Int,
            let to = args["to"] as? Int,
            let sizeSec = args["sizeSec"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "from, to(ms), sizeSec가 필요합니다", details: nil))
        return
      }
      reader.buckets(from: Self.date(from), to: Self.date(to), size: TimeInterval(sizeSec)) { Self.reply(result, $0) }
    case "writeTestSteps":
      let count = (call.arguments as? [String: Any])?["count"] as? Int ?? 50
      reader.writeTestSteps(count: count) { outcome in Self.reply(result, outcome.map { _ in nil as Any? }) }
    case "enableBackgroundDelivery":
      HealthSpikeObserver.enable { error in
        Self.reply(result, error.map { Result<Any?, Error>.failure($0) } ?? .success(nil))
      }
    case "readLog":
      result(HealthSpikeLog.read())
    case "appendLog":
      let args = call.arguments as? [String: Any]
      let event = args?["event"] as? String ?? "unknown"
      HealthSpikeLog.append(event: event, detail: args?["detail"] as? [String: Any] ?? [:]) { result(nil) }
    case "clearLog":
      HealthSpikeLog.clear()
      result(nil)
    case "deviceInfo":
      result([
        "platform": "ios",
        "model": UIDevice.current.model,
        "release": UIDevice.current.systemVersion,
        "healthDataAvailable": HKHealthStore.isHealthDataAvailable(),
        "stepCountingAvailable": PedometerReader.isAvailable,
      ])
    case "isStepCountingAvailable":
      result(PedometerReader.isAvailable)
    case "stepBuckets":
      guard let args = call.arguments as? [String: Any],
            let from = args["from"] as? Int,
            let to = args["to"] as? Int,
            let sizeSec = args["sizeSec"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "from, to(ms), sizeSec가 필요합니다", details: nil))
        return
      }
      PedometerReader.shared.buckets(from: Self.date(from), to: Self.date(to), size: TimeInterval(sizeSec)) { rows in
        DispatchQueue.main.async { result(rows) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func date(_ ms: Int) -> Date {
    Date(timeIntervalSince1970: Double(ms) / 1000)
  }

  /// HealthKit 콜백은 백그라운드 큐에서 오므로 Flutter 결과는 메인 스레드로 돌려준다.
  static func reply<T>(_ result: @escaping FlutterResult, _ outcome: Result<T, Error>) {
    DispatchQueue.main.async {
      switch outcome {
      case .success(let value):
        result(value)
      case .failure(let error):
        let nsError = error as NSError
        result(FlutterError(code: "\(nsError.domain):\(nsError.code)", message: nsError.localizedDescription, details: nil))
      }
    }
  }
}
