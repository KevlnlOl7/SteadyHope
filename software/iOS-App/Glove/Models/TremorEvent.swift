import Foundation
import UIKit

/// 動作分析紀錄模型，保存定期分析快照數據與使用者情境標籤
struct TremorEvent: Identifiable {

    /// 紀錄唯一識別碼
    let id: UUID

    /// 分析取樣時間戳記（取視窗最後一筆量測時間）
    let timestamp: Date

    /// 格式化時間文字標籤
    let timeLabel: String

    /// 4–6 Hz 震顫強度均方根值 RMS（單位：deg/s）
    let rmsValue: Double

    /// 主要頻率（單位：Hz，不可靠時為 0.0）
    let dominantFrequency: Double

    /// 分析視窗原始取樣點陣列（最近 400 筆數據，供計算 PSD 使用）
    let rawWindowData: [TremorDataPoint]

    /// 馬達致動狀態（最近 50 筆內是否有套用非零命令）
    let isMotorActive: Bool

    /// 使用者填寫的情境標籤
    var userTag: String = ""

    /// 使用者附加的照片清單
    var selectedImages: [UIImage] = []

    /// 標記該筆紀錄是否已儲存歸檔
    var isSaved: Bool = false

    /// 保存後端載入或明確指定的最近 50 筆馬達啟動比例
    private var explicitMotorOnFraction: Double?

    /// 初始化動作分析紀錄實體
    init(
        id: UUID = UUID(),
        timestamp: Date,
        timeLabel: String,
        rmsValue: Double,
        dominantFrequency: Double,
        rawWindowData: [TremorDataPoint] = [],
        isMotorActive: Bool? = nil,
        motorOnFraction: Double? = nil,
        userTag: String = "",
        selectedImages: [UIImage] = [],
        isSaved: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.timeLabel = timeLabel
        self.rmsValue = rmsValue
        self.dominantFrequency = dominantFrequency
        self.rawWindowData = rawWindowData
        // 依最近 50 筆（0.5 秒）判斷是否有命令套用
        self.isMotorActive = isMotorActive ?? rawWindowData.suffix(50).contains { $0.motorEnabled == 1 }
        self.explicitMotorOnFraction = motorOnFraction
        self.userTag = userTag
        self.selectedImages = selectedImages
        self.isSaved = isSaved
    }
}

extension TremorEvent {

    /// 最近 50 筆（0.5 秒）馬達處於致動狀態的比例（區間為 0.0 至 1.0）
    public var motorOnFraction: Double {
        if let explicit = explicitMotorOnFraction {
            return explicit
        }
        let latest50 = rawWindowData.suffix(50)
        guard !latest50.isEmpty else { return isMotorActive ? 1.0 : 0.0 }
        let activeCount = latest50.filter { $0.motorEnabled == 1 }.count
        return Double(activeCount) / Double(latest50.count)
    }

    /// 轉換為上傳至後端伺服器之 TremorAnalysisRecordDTO
    public func toAnalysisRecordDTO(
        sessionId: String,
        dataValid: Bool = true,
        frequencyReliable: Bool? = nil
    ) -> TremorAnalysisRecordDTO {
        // 若未指定可信度，以 dominantFrequency > 0 判定
        let reliable = frequencyReliable ?? (self.dominantFrequency > 0)
        
        return TremorAnalysisRecordDTO(
            id: self.id,
            sessionId: sessionId,
            recordedAt: self.timestamp,
            dominantFrequencyHz: reliable ? self.dominantFrequency : nil,
            tremorStrengthRmsDps: self.rmsValue,
            motorOnFraction: self.motorOnFraction,
            dataValid: dataValid,
            frequencyReliable: reliable,
            activityTag: self.userTag.isEmpty ? "未標記" : self.userTag,
            note: nil
        )
    }

    /// 從後端 TremorAnalysisRecordDTO 還原本地模型，完整保留 50 筆馬達小數比例
    public init(from dto: TremorAnalysisRecordDTO) {
        let tag = dto.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: dto.id,
            timestamp: dto.recordedAt,
            timeLabel: dto.recordedAt.formatted(date: .abbreviated, time: .standard),
            rmsValue: dto.tremorStrengthRmsDps ?? 0.0,
            dominantFrequency: (dto.frequencyReliable ? dto.dominantFrequencyHz : nil) ?? 0.0,
            rawWindowData: [],
            isMotorActive: dto.motorOnFraction > 0.0,
            motorOnFraction: dto.motorOnFraction,
            userTag: tag.isEmpty ? "未標記" : tag,
            selectedImages: [],
            isSaved: true
        )
    }
}
