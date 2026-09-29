import Foundation
import AppKit

/// ESP-IDF 日志级别（含解析后的显示颜色）
enum LogLevel: String, CaseIterable, Comparable {
    case verbose = "V"
    case debug = "D"
    case info = "I"
    case warning = "W"
    case error = "E"

    var value: Int {
        switch self {
        case .verbose: return 10
        case .debug: return 20
        case .info: return 30
        case .warning: return 40
        case .error: return 50
        }
    }

    var displayName: String {
        switch self {
        case .verbose: return "详细"
        case .debug: return "调试"
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }

    var color: NSColor {
        switch self {
        case .verbose: return .systemGray
        case .debug: return .systemGray
        case .info: return .systemGreen
        case .warning: return .systemOrange
        case .error: return .systemRed
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.value < rhs.value
    }
}

/// 一行日志（原始文本 + 解析结果 + 接收时间戳）
struct ESPLogEntry {
    let timestamp: String
    let raw: String
    let level: LogLevel?
    let tag: String?
    let message: String?

    var parsed: Bool { level != nil }
}

/// ESP-IDF 日志行解析器：`I (1234) Tag: message`
enum ESPLogParser {
    static let regex = try! NSRegularExpression(
        pattern: #"^([DVIWE]) \(\s*\d+\) ([A-Za-z0-9_.\-]+): ?(.*)$"#
    )

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func nowStamp() -> String {
        timeFormatter.string(from: Date())
    }

    static func parse(line: String) -> (level: LogLevel, tag: String, message: String)? {
        let ns = line as NSString
        guard
            let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: ns.length)
            ),
            match.range(at: 1).location != NSNotFound,
            let level = LogLevel(rawValue: ns.substring(with: match.range(at: 1)))
        else {
            return nil
        }
        let tag = ns.substring(with: match.range(at: 2))
        let message = ns.substring(with: match.range(at: 3))
        return (level, tag, message)
    }

    /// 组装 GUI 显示行（时间 + 级别 + tag + 消息）
    static func displayText(entry: ESPLogEntry) -> String {
        guard let parsed = parse(line: entry.raw) else {
            return entry.raw
        }
        return "\(entry.timestamp) [\(parsed.level.rawValue)] \(parsed.tag): \(parsed.message)"
    }

    /// 组装保存行（时间 + 原始行，与 python 版一致）
    static func saveLine(entry: ESPLogEntry) -> String {
        "\(entry.timestamp)\t\(entry.raw)"
    }
}

/// 过滤条件：tag 子串匹配（不区分大小写）+ 最低级别
struct LogFilter {
    var tags: [String] = []
    var minLevel: LogLevel?

    func accepts(_ entry: ESPLogEntry) -> Bool {
        guard let parsed = ESPLogParser.parse(line: entry.raw) else {
            return false
        }
        if !tags.isEmpty {
            let matched = tags.contains { t in
                parsed.tag.localizedCaseInsensitiveContains(t)
            }
            if !matched { return false }
        }
        if let min = minLevel, parsed.level.value < min.value {
            return false
        }
        return true
    }
}
