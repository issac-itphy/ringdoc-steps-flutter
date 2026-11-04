import Foundation
import UIKit

/// 스파이크 전용 기기 안 기록. Application Support/rdc_health_spike/log.jsonl에 한 줄에 JSON 하나.
/// shortcut: 크기 제한과 정리 없음, 정식화(G1) 때 디버그 기록(C12)으로 바꿈
public enum HealthSpikeLog {
  static let url: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("rdc_health_spike", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("log.jsonl")
  }()

  /// 앱 상태와 잠금 여부는 메인 스레드에서만 읽을 수 있어 기록도 메인 스레드에서 쓴다.
  public static func append(event: String, detail: [String: Any] = [:], then done: (() -> Void)? = nil) {
    DispatchQueue.main.async {
      let entry: [String: Any] = [
        "at": Int(Date().timeIntervalSince1970 * 1000),
        "event": event,
        "appState": appStateName(),
        "protectedData": UIApplication.shared.isProtectedDataAvailable,
        "detail": detail,
      ]
      if let data = try? JSONSerialization.data(withJSONObject: entry) {
        write(data + Data("\n".utf8))
      }
      done?()
    }
  }

  static func read() -> [[String: Any]] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap {
      try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
  }

  static func clear() {
    try? FileManager.default.removeItem(at: url)
  }

  private static func write(_ data: Data) {
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }

  private static func appStateName() -> String {
    switch UIApplication.shared.applicationState {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }

  static func detail(of error: Error) -> [String: Any] {
    let nsError = error as NSError
    return ["domain": nsError.domain, "code": nsError.code, "message": nsError.localizedDescription]
  }
}
