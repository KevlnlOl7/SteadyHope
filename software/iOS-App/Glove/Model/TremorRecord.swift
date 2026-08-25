import Foundation

/// 震顫分析完成後寫入資料庫同步之歷史紀錄資料模型
public struct TremorRecord: Codable, Identifiable {
    
    /// 紀錄唯一識別碼
    public var id: UUID

    /// 量測工作階段識別碼
    public var sessionId: String

    /// 紀錄時間戳記（毫秒，UTC）
    public var recordedAtUtcMs: Int64

    /// 主要震顫頻率（Hz，頻率不可靠時為 nil）
    public var dominantFrequencyHz: Double?

    /// 典型震顫強度均方根值（RMS，deg/s，資料無效時為 nil）
    public var tremorStrengthRmsDps: Double?

    /// 統計區間內馬達致動開啟時間比例（0.0 至 1.0）
    public var motorOnFraction: Double

    /// 感測器原始資料是否完整有效
    public var dataValid: Bool

    /// 主要頻率是否符合防呆門檻且具備可靠度
    public var frequencyReliable: Bool

    /// 當前生理或日常情境標籤（例如：休息、活動、服藥後等）
    public var activityTag: String

    /// 使用者自訂備註說明
    public var note: String?

    /// 初始化震顫歷史紀錄模型
    /// - Parameters:
    ///   - id: 紀錄唯一識別碼，預設為新產生的 UUID
    ///   - sessionId: 量測工作階段識別碼
    ///   - recordedAtUtcMs: 紀錄時間戳記（毫秒，UTC）
    ///   - dominantFrequencyHz: 主要震顫頻率（Hz）
    ///   - tremorStrengthRmsDps: 典型震顫強度均方根值（RMS，deg/s）
    ///   - motorOnFraction: 馬達致動開啟時間比例（0.0 至 1.0）
    ///   - dataValid: 感測器原始資料有效性旗標
    ///   - frequencyReliable: 頻率可靠度判定旗標
    ///   - activityTag: 生理或活動情境標籤
    ///   - note: 使用者自訂備註說明
    public init(
        id: UUID = UUID(),
        sessionId: String,
        recordedAtUtcMs: Int64,
        dominantFrequencyHz: Double? = nil,
        tremorStrengthRmsDps: Double? = nil,
        motorOnFraction: Double = 0.0,
        dataValid: Bool = true,
        frequencyReliable: Bool = false,
        activityTag: String = "休息",
        note: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.recordedAtUtcMs = recordedAtUtcMs
        self.dominantFrequencyHz = dominantFrequencyHz
        self.tremorStrengthRmsDps = tremorStrengthRmsDps
        self.motorOnFraction = motorOnFraction
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
        self.activityTag = activityTag
        self.note = note
    }
}
