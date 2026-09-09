import Foundation

/// 震顫分析紀錄資料傳輸物件 (DTO)
public struct TremorAnalysisRecordDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let recordedAt: Date
    public let dominantFrequencyHz: Double?
    public let tremorStrengthRmsDps: Double?
    public let motorOnFraction: Double
    public let dataValid: Bool
    public let frequencyReliable: Bool
    public let activityTag: String
    public let note: String?

    public init(
        id: UUID = UUID(),
        sessionId: String,
        recordedAt: Date,
        dominantFrequencyHz: Double?,
        tremorStrengthRmsDps: Double?,
        motorOnFraction: Double,
        dataValid: Bool,
        frequencyReliable: Bool,
        activityTag: String,
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
