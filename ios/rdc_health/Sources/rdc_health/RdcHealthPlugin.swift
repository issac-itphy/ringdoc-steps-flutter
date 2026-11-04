import Flutter
import UIKit

public class RdcHealthPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "rdc_health", binaryMessenger: registrar.messenger())
    let instance = RdcHealthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
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
