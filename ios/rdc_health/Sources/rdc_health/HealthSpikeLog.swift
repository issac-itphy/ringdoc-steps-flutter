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
        mirrorToDocuments()
      }
      done?()
    }
  }

  /// 파일 공유를 켠 앱(샘플 앱 Info.plist)에서만 Documents/log.txt에 읽기 쉬운 요약을 통째로 다시 써서, 개발자가 파일 앱으로 쌓이는지 본다.
  /// shortcut: Documents는 iCloud 백업에 들어가므로 테스트 기기 전용, 본 앱(G1)에는 가져가지 않음
  private static func mirrorToDocuments() {
    guard Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true else { return }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    // BOM: Android 사본과 같게, 보기 앱이 한글을 UTF-8로 읽게
    let text = "\u{FEFF}" + read().map(readable).joined(separator: "\n") + "\n"
    try? text.write(to: docs.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
  }

  /// 한 줄 요약: 시각, 사건, 앱 상태, 잠금, 새 샘플의 기기별 걸음, CoreMotion 15분 걸음, 오류 코드.
  static func readable(_ entry: [String: Any]) -> String {
    let at = (entry["at"] as? NSNumber)?.doubleValue ?? 0
    var parts = [
      timeFormatter.string(from: Date(timeIntervalSince1970: at / 1000)),
      (entry["event"] as? String ?? "").padding(toLength: 20, withPad: " ", startingAt: 0),
      (entry["appState"] as? String ?? "").padding(toLength: 10, withPad: " ", startingAt: 0),
    ]
    if entry["protectedData"] as? Bool == false { parts.append("잠금") }
    let detail = entry["detail"] as? [String: Any] ?? [:]
    if let samples = detail["samples"] as? [[String: Any]], !samples.isEmpty {
      var byDevice: [String: Int] = [:]
      for sample in samples {
        byDevice[sample["deviceModel"] as? String ?? "기타", default: 0] += (sample["count"] as? NSNumber)?.intValue ?? 0
      }
      let sums = byDevice.sorted { $0.key < $1.key }.map { "\($0.key) \(grouped($0.value))보" }
      parts.append("새 샘플 \(samples.count) (\(sums.joined(separator: ", ")))")
    } else if let count = detail["newSamples"] as? NSNumber {
      parts.append("새 샘플 \(count)")
    }
    if let steps = detail["pedometer15m"] as? NSNumber { parts.append("CoreMotion 15분 \(grouped(steps.intValue))보") }
    if let code = detail["code"] as? NSNumber { parts.append("오류 \(code)") }
    return parts.joined(separator: "  ")
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private static func grouped(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
  }

  static func read() -> [[String: Any]] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap {
      try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
  }

  static func clear() {
    try? FileManager.default.removeItem(at: url)
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? FileManager.default.removeItem(at: docs.appendingPathComponent("log.txt"))
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
