import CoreMotion
import Foundation

/// 스파이크 비교용 CoreMotion 걸음 조회. 시뮬레이터에는 걸음 센서가 없어 늘 사용 불가.
final class PedometerReader {
  static let shared = PedometerReader()

  private let pedometer = CMPedometer()

  static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

  /// [from, to)를 size초 칸으로 나눠 차례로 조회한다. 칸에 기록이 없어 오류가 나면 0보로 둔다.
  func buckets(from: Date, to: Date, size: TimeInterval, completion: @escaping ([[String: Any]]) -> Void) {
    guard Self.isAvailable, size > 0 else {
      completion([])
      return
    }
    var starts: [Date] = []
    var start = from
    while start < to {
      starts.append(start)
      start = start.addingTimeInterval(size)
    }
    var rows: [[String: Any]] = []
    func query(_ index: Int) {
      guard index < starts.count else {
        completion(rows)
        return
      }
      let slotStart = starts[index]
      let slotEnd = min(slotStart.addingTimeInterval(size), to)
      pedometer.queryPedometerData(from: slotStart, to: slotEnd) { data, _ in
        rows.append([
          "start": Int(slotStart.timeIntervalSince1970 * 1000),
          "end": Int(slotEnd.timeIntervalSince1970 * 1000),
          "steps": data?.numberOfSteps.intValue ?? 0,
        ])
        query(index + 1)
      }
    }
    query(0)
  }

  /// 최근 seconds초 걸음. 관찰 쿼리 기록에 붙여 잠금 상태에서도 CoreMotion이 읽히는지 본다.
  func recentSteps(seconds: TimeInterval, completion: @escaping (Result<Int, Error>) -> Void) {
    guard Self.isAvailable else {
      completion(.failure(NSError(domain: "rdc_health", code: 1, userInfo: [NSLocalizedDescriptionKey: "걸음 측정 사용 불가"])))
      return
    }
    let now = Date()
    pedometer.queryPedometerData(from: now.addingTimeInterval(-seconds), to: now) { data, error in
      if let error { completion(.failure(error)) } else { completion(.success(data?.numberOfSteps.intValue ?? 0)) }
    }
  }
}
