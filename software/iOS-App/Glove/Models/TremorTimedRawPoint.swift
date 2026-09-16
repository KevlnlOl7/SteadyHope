import Foundation

/// 帶有絕對時序之原始震顫取樣點領域模型，封裝解壓縮後對應的精確時間戳記與原始測量數據
struct TremorTimedRawPoint {
    /// 該取樣點記錄之絕對時間戳記（對應 TremorRawDataPointDTO.recordedAt）
    let timestamp: Date

    /// 本地慣性測量之單筆震顫數據點實體
    let point: TremorDataPoint
}
