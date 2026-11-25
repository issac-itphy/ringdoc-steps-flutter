import Flutter
import Foundation
import HealthKit

/// 네이티브 설정. UserDefaults 키는 모두 `rdc_health_` 접두사라 disable에서 한꺼번에 지운다.
enum RdcHealthSettings {
  static let prefix = "rdc_health_"
  static let enabled = prefix + "enabled"
  static let active = prefix + "active"
  static let userId = prefix + "userId"
  static let dispatcherHandle = prefix + "dispatcherHandle"
  static let handlerHandle = prefix + "handlerHandle"

  static var defaults: UserDefaults { .standard }

  static func clearAll() {
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }
}

/// 걸음 HKObserverQuery + 백그라운드 전달. 깨어나면 메인 엔진의 `rdc_health/background`로 `run`을 보낸다.
enum StepObserver {
  /// 플러그인 등록 때 채워진다. 엔진이 아직 없으면 nil.
  static var backgroundChannel: FlutterMethodChannel?

  // 결정: HealthKit 완료 콜백 대기 한도 25초. 백그라운드 실행 시간이 짧아 넘기면 어차피 OS가 끊는다
  static let handlerTimeout: TimeInterval = 25

  private static var query: HKObserverQuery?

  static func startIfEnabled() {
    if RdcHealthSettings.defaults.bool(forKey: RdcHealthSettings.enabled) { start() }
  }

  static func start() {
    guard query == nil else { return }
    let reader = HealthStepReader.shared
    let observer = HKObserverQuery(sampleType: reader.stepType, predicate: nil) { _, completionHandler, error in
      // 오류(예: 기기 잠김)면 일은 하지 않고 완료만 알린다. 다음 변경 때 다시 온다
      if error != nil { completionHandler() } else { wake(done: completionHandler) }
    }
    query = observer
    reader.store.execute(observer)
  }

  static func stop() {
    if let query { HealthStepReader.shared.store.stop(query) }
    query = nil
  }

  // 메인 스레드에서만 만진다
  private static var dartReady = false
  private static var pending: [() -> Void] = []

  /// Dart가 이 프로세스에서 setBackgroundHandler를 불렀다 = 메인 isolate의 `run` 처리기가 등록됐다.
  /// 그때까지 쌓인 깨움을 `run` 한 번으로 처리한다.
  static func dartRegistered(handle: Int) {
    dartReady = true
    guard !pending.isEmpty else { return }
    let waiting = pending
    pending = []
    sendRun(handle: handle) { waiting.forEach { $0() } }
  }

  private static func wake(done: @escaping () -> Void) {
    let defaults = RdcHealthSettings.defaults
    // 결정: active는 보지 않는다. setActive(false)는 기록만 멈추는 뜻이고 iOS엔 기록이 없다. 핸들러는 계속 돌아야 호스트가 판단(예: 로그아웃 14일 뒤 disable)할 수 있다
    guard defaults.bool(forKey: RdcHealthSettings.enabled) else {
      done()
      return
    }
    DispatchQueue.main.async {
      var finished = false
      let finish = {
        if !finished {
          finished = true
          done()
        }
      }
      // 결정: 앱이 죽어 있다 백그라운드로 뜬 경우 Dart main()이 처리기를 등록하기 전에 깨움이 온다. 완료를 쥐고 있다 등록 시점에 한꺼번에 처리한다
      if dartReady, let handle = defaults.object(forKey: RdcHealthSettings.handlerHandle) as? Int {
        sendRun(handle: handle, then: finish)
      } else {
        pending.append(finish)
      }
      // 결정: HealthKit 완료는 25초 안에 반드시 부른다(Dart가 끝내 등록하지 않아도)
      DispatchQueue.main.asyncAfter(deadline: .now() + handlerTimeout) { finish() }
    }
  }

  private static func sendRun(handle: Int, then finish: @escaping () -> Void) {
    guard let channel = backgroundChannel else {
      finish()
      return
    }
    // 결정: 성공, 오류(handler_failed/no_handler/미등록) 어느 쪽이든 응답이 오면 끝난 것으로 본다
    channel.invokeMethod("run", arguments: ["handlerHandle": handle]) { _ in finish() }
  }
}
