import Foundation

/// 震顫分析完成後寫入資料庫同步之歷史紀錄資料模型
public struct TremorRecord: Codable, Identifiable, Sendable {
    
    /// 紀錄唯一識別碼
    public var id: UUID

    /// 量測工作階段識別碼
    public var sessionId: String

    /// 紀錄時間戳記（ISO 8601 格式時間字串）
    public var recordedAt: String

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

    /// 當前生理或日常情境標籤（未標記時為 nil）
    public var activityTag: String?

    /// 使用者自訂備註說明
    public var note: String?

    /// 序列化與反序列化鍵值對應列舉
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case recordedAt
        case dominantFrequencyHz = "dominant_frequency_hz"
        case tremorStrengthRmsDps = "tremor_strength_rms_dps"
        case motorOnFraction = "motor_on_fraction"
        case dataValid = "data_valid"
        case frequencyReliable = "frequency_reliable"
        case activityTag = "activity_tag"
        case note
    }
    
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
        sessionId: String = UUID().uuidString,
        recordedAt: String,
        dominantFrequencyHz: Double? = nil,
        tremorStrengthRmsDps: Double? = nil,
        motorOnFraction: Double = 0.0,
        dataValid: Bool = true,
        frequencyReliable: Bool = false,
        activityTag: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.dominantFrequencyHz = dominantFrequencyHz
        self.tremorStrengthRmsDps = tremorStrengthRmsDps
        self.motorOnFraction = motorOnFraction
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
        self.activityTag = activityTag
        self.note = note
    }
}
