import Foundation
import HealthKit

/// HealthKit 걸음(stepCount) 조회.
final class HealthStepReader {
  static let shared = HealthStepReader()

  let store = HKHealthStore()
  let stepType = HKQuantityType(.stepCount)

  /// 읽기와 쓰기(샘플 앱 시험용) 권한 요청. HealthKit은 읽기 허용 여부를 알려 주지 않는다.
  func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void) {
    guard HKHealthStore.isHealthDataAvailable() else {
      completion(.success(false))
      return
    }
    store.requestAuthorization(toShare: [stepType], read: [stepType]) { ok, error in
      if let error { completion(.failure(error)) } else { completion(.success(ok)) }
    }
  }

  func samples(from: Date, to: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    let query = HKSampleQuery(
      sampleType: stepType,
      predicate: HKQuery.predicateForSamples(withStart: from, end: to),
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    ) { _, samples, error in
      if let error {
        completion(.failure(error))
        return
      }
      completion(.success((samples as? [HKQuantitySample] ?? []).map(Self.toMap)))
    }
    store.execute(query)
  }

  /// S8: [size] 칸 걸음 합계. 통계 쿼리라 iPhone과 워치가 같은 시간에 센 걸음을 HealthKit 출처 우선순위로 한 번만 센다.
  func buckets(from: Date, to: Date, size: TimeInterval, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    var interval = DateComponents()
    interval.second = Int(size)
    let query = HKStatisticsCollectionQuery(
      quantityType: stepType,
      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to),
      options: .cumulativeSum,
      anchorDate: Calendar.current.startOfDay(for: from),
      intervalComponents: interval
    )
    query.initialResultsHandler = { _, collection, error in
      if let error {
        completion(.failure(error))
        return
      }
      var rows: [[String: Any]] = []
      collection?.enumerateStatistics(from: from, to: to) { stats, _ in
        rows.append([
          "start": Int(stats.startDate.timeIntervalSince1970 * 1000),
          "end": Int(stats.endDate.timeIntervalSince1970 * 1000),
          "steps": Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0),
        ])
      }
      completion(.success(rows))
    }
    store.execute(query)
  }

  /// 샘플 앱 시험용: 지금부터 1분 전까지 걸음 샘플 하나를 쓴다. 정식화(G1) 때 제거.
  func writeTestSteps(count: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
    let end = Date()
    let sample = HKQuantitySample(
      type: stepType,
      quantity: HKQuantity(unit: .count(), doubleValue: Double(count)),
      start: end.addingTimeInterval(-60),
      end: end
    )
    store.save(sample) { ok, error in
      if let error { completion(.failure(error)) } else { completion(.success(ok)) }
    }
  }

  static func toMap(_ sample: HKQuantitySample) -> [String: Any] {
    let source = sample.sourceRevision.source
    return [
      "uuid": sample.uuid.uuidString,
      "start": Int(sample.startDate.timeIntervalSince1970 * 1000),
      "end": Int(sample.endDate.timeIntervalSince1970 * 1000),
      "count": Int(sample.quantity.doubleValue(for: .count())),
      "sourceName": source.name,
      "sourceBundleId": source.bundleIdentifier,
      // 채널 코덱은 Swift Optional을 못 넘기므로 nil은 NSNull로
      "deviceModel": sample.device?.model ?? NSNull(),
      "deviceName": sample.device?.name ?? NSNull(),
    ]
  }
}
