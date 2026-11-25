import CoreMotion
import Foundation

/// CoreMotion 걸음 조회. 시뮬레이터에는 걸음 센서가 없어 늘 사용 불가.
final class PedometerReader {
  static let shared = PedometerReader()

  private let pedometer = CMPedometer()

  static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

  /// 동작 및 피트니스 권한이 거부/제한이면 false. 센서가 없으면 거부가 아니므로 true.
  static var isPermitted: Bool {
    switch CMPedometer.authorizationStatus() {
    case .denied, .restricted: return false
    default: return true
    }
  }

  /// 아주 작은 조회 하나로 권한 안내창을 띄운다.
  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    guard Self.isAvailable else {
      completion(true)
      return
    }
    let now = Date()
    pedometer.queryPedometerData(from: now.addingTimeInterval(-1), to: now) { _, _ in
      completion(Self.isPermitted)
    }
  }

  /// [from, to)를 size초 칸으로 나눠 차례로 조회한다. 칸은 에포크 기준으로 맞추고 마지막 칸은 to에서 자른다.
  /// 칸에 기록이 없어 오류가 나면 0보로 둔다. 센서가 없거나 권한이 없으면 빈 목록.
  func buckets(
    from: Date, to: Date, size: TimeInterval,
    completion: @escaping ([(start: Date, end: Date, steps: Int)]) -> Void
  ) {
    guard Self.isAvailable, Self.isPermitted, size > 0 else {
      completion([])
      return
    }
    var starts: [Date] = []
    var start = Date(timeIntervalSince1970: (from.timeIntervalSince1970 / size).rounded(.down) * size)
    while start < to {
      starts.append(start)
      start = start.addingTimeInterval(size)
    }
    var rows: [(start: Date, end: Date, steps: Int)] = []
    func query(_ index: Int) {
      guard index < starts.count else {
        completion(rows)
        return
      }
      let slotStart = max(starts[index], from)
      let slotEnd = min(starts[index].addingTimeInterval(size), to)
      pedometer.queryPedometerData(from: slotStart, to: slotEnd) { data, _ in
        rows.append((slotStart, slotEnd, data?.numberOfSteps.intValue ?? 0))
        query(index + 1)
      }
    }
    query(0)
  }
}
