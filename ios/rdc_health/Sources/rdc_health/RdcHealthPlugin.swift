import Flutter
import HealthKit
import UIKit

public class RdcHealthPlugin: NSObject, FlutterPlugin {
  // 결정: API에 임계값 인자가 없다(설계). 움직임 구간 = 5분 칸에 50보 이상. 열린 질문은 스펙에 기록
  static let segmentMinutes = 5
  static let segmentMinSteps = 50

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "rdc_health", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(RdcHealthPlugin(), channel: channel)
    StepObserver.backgroundChannel = FlutterMethodChannel(
      name: "rdc_health/background", binaryMessenger: registrar.messenger())
  }

  /// 호스트 앱 AppDelegate의 didFinishLaunching 첫 줄에서 부른다.
  /// Apple 문서가 관찰 쿼리를 앱 시작 직후 다시 등록하라고 한다. 켜져 있을 때만 만든다.
  public static func registerObserverIfEnabled() {
    StepObserver.startIfEnabled()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = RdcHealthSettings.defaults
    switch call.method {
    case "availability":
      result(HKHealthStore.isHealthDataAvailable() ? "available" : "unsupported")

    case "requestPermissions":
      requestPermissions(result)

    case "enable":
      guard let userId = (call.arguments as? [String: Any])?["userId"] as? String else {
        result(Self.badArgs("userId가 필요합니다"))
        return
      }
      defaults.set(true, forKey: RdcHealthSettings.enabled)
      defaults.set(true, forKey: RdcHealthSettings.active)
      defaults.set(userId, forKey: RdcHealthSettings.userId)
      StepObserver.start()
      let reader = HealthStepReader.shared
      reader.store.enableBackgroundDelivery(for: reader.stepType, frequency: .hourly) { _, error in
        Self.reply(result, error.map { Result<Any?, Error>.failure($0) } ?? .success(nil))
      }

    case "setActive":
      guard let active = (call.arguments as? [String: Any])?["active"] as? Bool else {
        result(Self.badArgs("active가 필요합니다"))
        return
      }
      // 결정: 꺼도 관찰 쿼리는 그대로 두고, 깨움 때 핸들러 실행만 건너뛴다
      defaults.set(active, forKey: RdcHealthSettings.active)
      result(nil)

    case "disable":
      StepObserver.stop()
      // 결정: 이 플러그인은 파일을 쓰지 않는다(앵커 없음). 지울 것은 UserDefaults뿐
      RdcHealthSettings.clearAll()
      let reader = HealthStepReader.shared
      // 결정: 해제 실패는 무시한다. 이미 꺼져 있어도 disable은 성공해야 한다(멱등)
      reader.store.disableBackgroundDelivery(for: reader.stepType) { _, _ in
        DispatchQueue.main.async { result(nil) }
      }

    case "setBackgroundHandler":
      guard let args = call.arguments as? [String: Any],
            let dispatcher = args["dispatcherHandle"] as? Int,
            let handler = args["handlerHandle"] as? Int
      else {
        result(Self.badArgs("dispatcherHandle, handlerHandle가 필요합니다"))
        return
      }
      defaults.set(dispatcher, forKey: RdcHealthSettings.dispatcherHandle)
      defaults.set(handler, forKey: RdcHealthSettings.handlerHandle)
      StepObserver.dartRegistered(handle: handler)
      result(nil)

    case "moveSegments":
      guard let (from, to) = Self.range(call) else {
        result(Self.badArgs("from, to(ms)가 필요합니다"))
        return
      }
      moveSegments(from: from, to: to, result)

    case "hourlySteps":
      guard let (from, to) = Self.range(call) else {
        result(Self.badArgs("from, to(ms)가 필요합니다"))
        return
      }
      var hour = DateComponents()
      hour.hour = 1
      HealthStepReader.shared.sums(from: from, to: to, interval: hour) { outcome in
        // 결정: 걸음이 0인 시간도 포함한다. 호스트가 "0보"와 "칸 없음(조회 실패/범위 밖)"을 구분하도록
        // 결정: HealthKit 오류는 빈 목록으로 돌려준다(읽기 권한 거부와 구분 불가라서)
        let rows = ((try? outcome.get()) ?? []).map { ["hourStart": Self.ms($0.start), "steps": $0.steps] }
        DispatchQueue.main.async { result(rows) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermissions(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(false)
      return
    }
    HealthStepReader.shared.requestAuthorization { outcome in
      // 결정: HealthKit은 읽기 허용 여부를 알려 주지 않는다. 요청이 오류 없이 끝나면 true로 본다
      if case .failure = outcome {
        DispatchQueue.main.async { result(false) }
        return
      }
      PedometerReader.shared.requestAuthorization { permitted in
        DispatchQueue.main.async { result(permitted) }
      }
    }
  }

  /// CoreMotion(즉시, 폰만)과 HealthKit(늦게 도착, 폰+워치 중복 제거)을 합쳐 시작 시각순으로 돌려준다.
  private func moveSegments(from: Date, to: Date, _ result: @escaping FlutterResult) {
    let size = TimeInterval(Self.segmentMinutes * 60)
    PedometerReader.shared.buckets(from: from, to: to, size: size) { motion in
      var interval = DateComponents()
      interval.minute = Self.segmentMinutes
      HealthStepReader.shared.sums(from: from, to: to, interval: interval) { outcome in
        // 결정: HealthKit 오류는 건너뛰고 CoreMotion 결과만 돌려준다
        let health = (try? outcome.get()) ?? []
        let rows = (motion.map { ($0, "coreMotion") } + health.map { ($0, "healthKit") })
          .filter { $0.0.steps >= Self.segmentMinSteps }
          .sorted { $0.0.start < $1.0.start }
          .map { ["start": Self.ms($0.0.start), "end": Self.ms($0.0.end), "steps": $0.0.steps, "source": $0.1] as [String: Any] }
        DispatchQueue.main.async { result(rows) }
      }
    }
  }

  static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

  static func range(_ call: FlutterMethodCall) -> (Date, Date)? {
    guard let args = call.arguments as? [String: Any],
          let from = args["from"] as? Int,
          let to = args["to"] as? Int
    else { return nil }
    return (Date(timeIntervalSince1970: Double(from) / 1000), Date(timeIntervalSince1970: Double(to) / 1000))
  }

  static func badArgs(_ message: String) -> FlutterError {
    FlutterError(code: "bad_args", message: message, details: nil)
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
