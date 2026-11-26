import Foundation
import HealthKit

/// HealthKit 걸음(stepCount) 읽기.
final class HealthStepReader {
  static let shared = HealthStepReader()

  let store = HKHealthStore()
  let stepType = HKQuantityType(.stepCount)

  /// 읽기 권한만 요청한다. 쓰기는 하지 않는다.
  func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
    store.requestAuthorization(toShare: nil, read: [stepType]) { _, error in
      if let error { completion(.failure(error)) } else { completion(.success(())) }
    }
  }

  /// [from, to)를 interval 칸으로 나눈 걸음 합계. 통계 쿼리라 iPhone과 워치가 같은 시간에 센 걸음은 한 번만 센다.
  /// 칸은 로컬 자정을 기준으로 나뉘고, 데이터가 없는 칸도 0으로 돌아온다.
  func sums(
    from: Date, to: Date, interval: DateComponents,
    completion: @escaping (Result<[(start: Date, end: Date, steps: Int)], Error>) -> Void
  ) {
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
      var rows: [(start: Date, end: Date, steps: Int)] = []
      collection?.enumerateStatistics(from: from, to: to) { stats, _ in
        // 결정: enumerate가 to 이후에 시작하는 칸을 하나 더 줄 수 있어 to 전에 시작하는 칸만 쓴다
        guard stats.startDate < to else { return }
        rows.append((stats.startDate, stats.endDate, Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
      }
      completion(.success(rows))
    }
    store.execute(query)
  }
}
