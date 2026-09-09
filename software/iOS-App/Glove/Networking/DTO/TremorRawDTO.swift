import Foundation

/// 原始震顫數據點傳輸物件 (DTO)，用於本機序列化為 JSON 後進行二進位壓縮處理
public struct TremorRawDataPointDTO: Codable, Sendable {
    let sequence: UInt32
    let sampleTickMs: UInt32
    let recordedAt: Date
    let gyroXDps: Double
    let gyroYDps: Double
    let gyroZDps: Double
    let sensorValid: UInt8
    let motorEnabled: UInt8

    init(
        sequence: UInt32,
        sampleTickMs: UInt32,
        recordedAt: Date,
        gyroXDps: Double,
        gyroYDps: Double,
        gyroZDps: Double,
        sensorValid: UInt8,
        motorEnabled: UInt8
    ) {
        self.sequence = sequence
        self.sampleTickMs = sampleTickMs
        self.recordedAt = recordedAt
        self.gyroXDps = gyroXDps
        self.gyroYDps = gyroYDps
        self.gyroZDps = gyroZDps
        self.sensorValid = sensorValid
        self.motorEnabled = motorEnabled
    }
}

/// 後端接收之壓縮二進位上傳請求傳輸物件 (DTO)
struct TremorRawUploadRequestDTO: Codable, Sendable {
    let sessionId: String
    let sampleCount: Int
    let compressedData: Data

    init(sessionId: String, sampleCount: Int, compressedData: Data) {
        self.sessionId = sessionId
        self.sampleCount = sampleCount
        self.compressedData = compressedData
    }
}

/// 後端資料庫原始震顫紀錄對應之傳輸物件 (DTO)
public struct RawTremorDataDTO: Codable, Sendable, Identifiable {
    public let id: Int?
    public let userID: Int
    public let sessionId: String
    public let sampleCount: Int
    public let compressedData: Data
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case sessionId
        case sampleCount
        case compressedData
        case createdAt
    }

    /// 使用 zlib 演算法解壓縮二進位資料並反序列化還原為取樣點傳輸物件陣列
    /// - Returns: 解碼完成之 TremorRawDataPointDTO 物件陣列
    /// - Throws: 當解壓縮流程失敗或 JSON 反序列化格式不符時拋出錯誤
    public func decompressPoints() throws -> [TremorRawDataPointDTO] {
        // 使用 NSData 提供的 zlib 演算法進行二進位數據解壓縮
        let decompressedData = try (compressedData as NSData).decompressed(using: .zlib) as Data

        // 建立專用 JSON 解碼器進行反序列化，並設定 ISO 8601 日期解碼策略以解析時間戳記
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 若原始序列化採用預設 CamelCase 欄位命名，直接解碼回傳
        if let points = try? decoder.decode([TremorRawDataPointDTO].self, from: decompressedData) {
            return points
        }

        // 若原始序列化帶有 SnakeCase 轉換，使用 convertFromSnakeCase 容錯解析回傳
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([TremorRawDataPointDTO].self, from: decompressedData)
    }
}
