import Foundation
import UIKit

/// 顯著震顫事件模型，專供事件佇列列表與即時震顫事件追蹤使用
struct TremorEvent: Identifiable {

    /// 震顫事件唯一識別碼
    let id: UUID

    /// 震顫事件發生時間（標準 Date 物件）
    let timestamp: Date

    /// 格式化時間文字標籤
    let timeLabel: String

    /// 震顫強度均方根值 RMS（單位：deg/s）
    let rmsValue: Double

    /// 震顫主要頻率（單位：Hz）
    let dominantFrequency: Double

    /// 分析視窗原始取樣點陣列（預設為 400 筆數據，供計算 PSD 功率譜密度使用）
    let rawWindowData: [TremorDataPoint]

    /// 馬達致動狀態（true 代表事件發生期間馬達有啟動）
    let isMotorActive: Bool

    /// 使用者填寫的情境標籤
    var userTag: String = ""

    /// 使用者選取並附加的照片清單
    var selectedImages: [UIImage] = []

    /// 標記該筆事件是否已儲存歸檔至本地或後端資料庫
    var isSaved: Bool = false

    /// 初始化顯著震顫事件模型實體
    /// - Parameters:
    ///   - id: 事件唯一識別碼，預設自動生成 UUID
    ///   - timestamp: 事件時間戳記
    ///   - timeLabel: 顯示用時間字串
    ///   - rmsValue: 震顫強度 RMS
    ///   - dominantFrequency: 主要震顫頻率
    ///   - rawWindowData: 原始取樣資料點陣列，預設為空陣列
    ///   - isMotorActive: 馬達是否啟動，若未指定則自動依據取樣點內容判斷
    ///   - userTag: 使用者情境標籤，預設為空字串
    ///   - selectedImages: 附加圖片陣列，預設為空陣列
    ///   - isSaved: 儲存歸檔狀態，預設為 false
    init(
        id: UUID = UUID(),
        timestamp: Date,
        timeLabel: String,
        rmsValue: Double,
        dominantFrequency: Double,
        rawWindowData: [TremorDataPoint] = [],
        isMotorActive: Bool? = nil,
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
        self.isMotorActive = isMotorActive ?? rawWindowData.contains { $0.motorEnabled == 1 }
        self.userTag = userTag
        self.selectedImages = selectedImages
        self.isSaved = isSaved
    }
}

/// 擴充 TremorEvent 提供資料傳輸物件轉換與運算邏輯
extension TremorEvent {

    /// 計算視窗取樣數據中馬達處於致動狀態的比例（數值區間為 0.0 至 1.0）
    public var motorOnFraction: Double {
        guard !rawWindowData.isEmpty else { return isMotorActive ? 1.0 : 0.0 }
        let activeCount = rawWindowData.filter { $0.motorEnabled == 1 }.count
        return Double(activeCount) / Double(rawWindowData.count)
    }

    /// 將本地 TremorEvent 模型轉換為上傳至後端伺服器之 TremorAnalysisRecordDTO
    /// - Parameters:
    ///   - sessionId: 關聯之量測會話識別碼
    ///   - dataValid: 標記此批數據是否有效，預設為 true
    ///   - frequencyReliable: 標記主要頻率計算結果是否可信，預設為 true
    /// - Returns: 封裝完成的 TremorAnalysisRecordDTO 資料傳輸物件
    public func toAnalysisRecordDTO(
        sessionId: String,
        dataValid: Bool = true,
        frequencyReliable: Bool = true
    ) -> TremorAnalysisRecordDTO {
        TremorAnalysisRecordDTO(
            id: self.id,
            sessionId: sessionId,
            recordedAt: self.timestamp,
            dominantFrequencyHz: self.dominantFrequency > 0 ? self.dominantFrequency : nil,
            tremorStrengthRmsDps: self.rmsValue,
            motorOnFraction: self.motorOnFraction,
            dataValid: dataValid,
            frequencyReliable: frequencyReliable,
            activityTag: self.userTag.isEmpty ? "未標記" : self.userTag,
            note: nil
        )
    }

    /// 依據後端伺服器回傳之 TremorAnalysisRecordDTO 資料傳輸物件建構本地 TremorEvent 模型
    /// - Parameter dto: 從伺服器取得之震顫分析紀錄資料傳輸物件
    public init(from dto: TremorAnalysisRecordDTO) {
        let tag = dto.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: dto.id,
            timestamp: dto.recordedAt,
            timeLabel: dto.recordedAt.formatted(date: .abbreviated, time: .standard),
            rmsValue: dto.tremorStrengthRmsDps ?? 0.0,
            dominantFrequency: dto.dominantFrequencyHz ?? 0.0,
            rawWindowData: [],
            isMotorActive: dto.motorOnFraction > 0.0,
            userTag: tag.isEmpty ? "未標記" : tag,
            selectedImages: [],
            isSaved: true
        )
    }
}
