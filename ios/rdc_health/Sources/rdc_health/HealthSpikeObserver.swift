import Foundation
import HealthKit
import UIKit

/// 스파이크 전용 걸음 관찰 쿼리. 새 샘플을 기록 파일에 남기고, Flutter가 떠 있으면 onSamples로 넘긴다.
public enum HealthSpikeObserver {
  /// 플러그인이 등록될 때 채널 호출을 연결한다. 엔진이 없으면 nil.
  static var onSamples: (([[String: Any]]) -> Void)?

  private static var query: HKObserverQuery?
  private static var watchingLock = false
  private static let observingKey = "rdc_health_spike_observing"
  private static let anchorKey = "rdc_health_spike_anchor"

  /// AppDelegate의 didFinishLaunching 첫 줄에서 부른다. Apple 문서가 관찰 쿼리를 앱 시작 직후 등록하라고 하기 때문.
  public static func bootstrap() {
    HealthSpikeLog.append(event: "bootstrap")
    watchLockChanges()
    if UserDefaults.standard.bool(forKey: observingKey) { start() }
  }

  static func enable(completion: @escaping (Error?) -> Void) {
    UserDefaults.standard.set(true, forKey: observingKey)
    let reader = HealthStepReader.shared
    reader.store.enableBackgroundDelivery(for: reader.stepType, frequency: .hourly) { _, error in
      DispatchQueue.main.async {
        start()
        let detail = error.map(HealthSpikeLog.detail(of:)) ?? [:]
        HealthSpikeLog.append(event: "observer_registered", detail: detail) { completion(error) }
      }
    }
  }

  private static func start() {
    guard query == nil else { return }
    let reader = HealthStepReader.shared
    let observer = HKObserverQuery(sampleType: reader.stepType, predicate: nil) { _, completionHandler, error in
      if let error {
        HealthSpikeLog.append(event: "observer_error", detail: HealthSpikeLog.detail(of: error), then: completionHandler)
        return
      }
      fetchNewSamples(then: completionHandler)
    }
    query = observer
    reader.store.execute(observer)
  }

  /// 앵커 뒤로 새로 들어온 샘플만 받는다. 앵커가 없으면 최근 24시간만.
  private static func fetchNewSamples(then done: @escaping () -> Void) {
    let reader = HealthStepReader.shared
    let anchor = loadAnchor()
    let predicate = anchor == nil
      ? HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-24 * 3600), end: nil)
      : nil
    let anchored = HKAnchoredObjectQuery(
      type: reader.stepType, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit
    ) { _, added, _, newAnchor, error in
      if let error {
        // 기기가 잠겨 있으면 여기서 errorDatabaseInaccessible이 온다
        HealthSpikeLog.append(event: "observer_error", detail: HealthSpikeLog.detail(of: error), then: done)
        return
      }
      if let newAnchor { saveAnchor(newAnchor) }
      let now = Date()
      let samples = added as? [HKQuantitySample] ?? []
      let maps = samples.map(HealthStepReader.toMap)
      let logged = samples.map { sample -> [String: Any] in
        var map = HealthStepReader.toMap(sample)
        map["delaySec"] = Int(now.timeIntervalSince(sample.endDate))
        return map
      }
      DispatchQueue.main.async {
        var sent = false
        if !maps.isEmpty, let onSamples {
          onSamples(maps)
          sent = true
        }
        HealthSpikeLog.append(
          event: "observer_fired",
          detail: ["newSamples": maps.count, "samples": logged, "sentToDart": sent],
          then: done
        )
      }
    }
    reader.store.execute(anchored)
  }

  private static func watchLockChanges() {
    guard !watchingLock else { return }
    watchingLock = true
    let center = NotificationCenter.default
    center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
      HealthSpikeLog.append(event: "unlocked")
    }
    center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
      HealthSpikeLog.append(event: "locked")
    }
  }

  private static func loadAnchor() -> HKQueryAnchor? {
    guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
  }

  private static func saveAnchor(_ anchor: HKQueryAnchor) {
    let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    UserDefaults.standard.set(data, forKey: anchorKey)
  }
}
