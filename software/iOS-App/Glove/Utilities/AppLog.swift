import Foundation
import OSLog

public enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.steadyhope.app"
    private static let logger = Logger(subsystem: subsystem, category: "SteadyHope")

    /// 用於一般偵錯、流程追蹤（僅在 DEBUG 模式下輸出）
    public static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        logger.debug("[\(fileName):\(line)] \(function) - \(message)")
        #endif
    }

    /// 用於錯誤、解析失敗、異常狀態
    public static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        logger.error("[\(fileName):\(line)] \(function) - \(message)")
    }
}
