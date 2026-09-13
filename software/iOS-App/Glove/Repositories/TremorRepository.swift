import Foundation

protocol TremorRepositoryProtocol {
    /// 同步單一震顫事件所包含的原始數據至伺服器
    func syncRawEventData(event: TremorEvent, sessionId: String) async throws

    /// 批次壓縮並上傳原始感測數據點至伺服器
    func syncRawData(sessionId: String, rawPoints: [TremorDataPoint], baseDate: Date) async throws

    /// 上傳單筆震顫分析結果紀錄至伺服器
    func syncAnalysisResult(record: TremorAnalysisRecordDTO) async throws

    /// 上傳分析紀錄的別名方法
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO) async throws

    /// 將舊版震顫事件轉換並同步為標準分析紀錄
    func syncEventAsAnalysisRecord(event: TremorEvent, sessionId: String) async throws

    /// 批次同步多筆震顫事件為分析紀錄
    func syncBatchEvents(_ events: [TremorEvent], sessionId: String) async throws

    /// 自伺服器取得歷史原始感測資料點陣列
    func fetchRawDataHistory() async throws -> [TremorDataPoint]

    /// 自伺服器取得帶有時間標記的歷史原始感測資料點陣列
    func fetchTimedRawDataHistory() async throws -> [TremorTimedRawPoint]

    /// 自伺服器取得歷史震顫分析紀錄清單
    func fetchAnalysisHistory() async throws -> [TremorAnalysisRecordDTO]
}

/// 震顫資料儲存庫實作類別，負責協調 API 服務與身分驗證憑證完成資料同步與讀取
final class TremorRepository: TremorRepositoryProtocol {
    /// 遠端 API 服務實體
    private let apiService: TremorAPIServiceProtocol

    /// 身分驗證 Token 提供者閉包
    private let tokenProvider: () -> String?

    /// 初始化儲存庫並注入 API 服務與 Token 提供者
    init(
        apiService: TremorAPIServiceProtocol = TremorAPIService.shared,
        tokenProvider: @escaping () -> String? = { AuthManager.shared.getToken() }
    ) {
        self.apiService = apiService
        self.tokenProvider = tokenProvider
    }

    /// 驗證並取得當前有效的身分驗證 Token
    private func getValidToken() throws -> String {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NetworkError.unauthorized
        }
        return token
    }

    /// 同步單一震顫事件原始數據
    func syncRawEventData(event: TremorEvent, sessionId: String) async throws {
        try await syncRawData(sessionId: sessionId, rawPoints: event.rawWindowData, baseDate: event.timestamp)
    }

    /// 批次壓縮並上傳原始感測數據點
    func syncRawData(sessionId: String, rawPoints: [TremorDataPoint], baseDate: Date) async throws {
        guard !rawPoints.isEmpty else {
            return
        }

        let token = try getValidToken()
        let firstTick = rawPoints.first?.sampleTickMs ?? 0

        let dtos = rawPoints.map { point -> TremorRawDataPointDTO in
            let pointDate: Date
            if let recordedAt = point.recordedAt {
                pointDate = recordedAt
            } else {
                let deltaTick = point.sampleTickMs &- firstTick
                pointDate = baseDate.addingTimeInterval(Double(deltaTick) / 1000.0)
            }

            return TremorRawDataPointDTO(
                sequence: UInt32(point.sequence),
                sampleTickMs: UInt32(point.sampleTickMs),
                recordedAt: pointDate,
                gyroXDps: point.gyroXDps,
                gyroYDps: point.gyroYDps,
                gyroZDps: point.gyroZDps,
                sensorValid: UInt8(point.sensorValid),
                motorEnabled: UInt8(point.motorEnabled)
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(dtos)
        let compressedData = try (jsonData as NSData).compressed(using: .zlib) as Data

        let payload = TremorRawUploadRequestDTO(
            sessionId: sessionId,
            sampleCount: rawPoints.count,
            compressedData: compressedData
        )

        try await apiService.uploadRawData(payload, token: token)
    }

    /// 上傳單筆震顫分析結果紀錄
    func syncAnalysisResult(record: TremorAnalysisRecordDTO) async throws {
        let token = try getValidToken()
        try await apiService.uploadAnalysisRecord(record, token: token)
    }

    /// 上傳分析紀錄的別名方法
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO) async throws {
        try await syncAnalysisResult(record: record)
    }

    /// 將本地震顫事件轉換為標準分析紀錄 DTO 並同步上傳至後端伺服器
    /// - Parameters:
    ///   - event: 本地顯著震顫事件模型
    ///   - sessionId: 關聯之量測會話識別碼
    func syncEventAsAnalysisRecord(event: TremorEvent, sessionId: String) async throws {
        let hasReliableFrequency = event.dominantFrequency > 0
        let record = TremorAnalysisRecordDTO(
            id: event.id,
            sessionId: sessionId,
            recordedAt: event.timestamp,
            dominantFrequencyHz: hasReliableFrequency ? event.dominantFrequency : nil,
            tremorStrengthRmsDps: event.rmsValue,
            motorOnFraction: event.motorOnFraction,
            dataValid: true,
            frequencyReliable: hasReliableFrequency,
            activityTag: event.userTag.isEmpty ? "未標記" : event.userTag,
            note: nil
        )

        try await syncAnalysisResult(record: record)
    }
    
    /// 批次同步多筆震顫事件為分析紀錄
    /// - Parameters:
    ///   - events: 待同步之震顫事件陣列
    ///   - sessionId: 關聯之量測會話識別碼
    func syncBatchEvents(_ events: [TremorEvent], sessionId: String) async throws {
        guard !events.isEmpty else { return }
        for event in events {
            try await syncEventAsAnalysisRecord(event: event, sessionId: sessionId)
        }
    }

    /// 取得歷史原始取樣點清單（相容舊介面，剝除時間資訊僅回傳 TremorDataPoint）
    /// - Returns: 歷史震顫取樣點陣列
    func fetchRawDataHistory() async throws -> [TremorDataPoint] {
        try await fetchTimedRawDataHistory().map(\.point)
    }

    /// 下載歷史原始數據封包並透過 zlib 解壓縮，還原各取樣點之絕對時間戳記
    /// - Returns: 依時間由舊至新排序之 TremorTimedRawPoint 陣列
    func fetchTimedRawDataHistory() async throws -> [TremorTimedRawPoint] {
        let token = try getValidToken()
        let rawDTOs = try await apiService.fetchRawDataHistory(token: token)
        var allPoints: [TremorTimedRawPoint] = []

        for rawDTO in rawDTOs {
            guard let decoded = try? rawDTO.decompressPoints() else {
                continue
            }

            allPoints.append(
                contentsOf: decoded.map { dto in
                    let point = TremorDataPoint(
                        sequence: dto.sequence,
                        sampleTickMs: dto.sampleTickMs,
                        gyroXDps: dto.gyroXDps,
                        gyroYDps: dto.gyroYDps,
                        gyroZDps: dto.gyroZDps,
                        sensorValid: dto.sensorValid,
                        motorEnabled: dto.motorEnabled,
                        recordedAt: dto.recordedAt
                    )

                    return TremorTimedRawPoint(
                        timestamp: dto.recordedAt,
                        point: point
                    )
                }
            )
        }

        return allPoints.sorted { $0.timestamp < $1.timestamp }
    }

    /// 向後端查詢所有歷史震顫特徵分析紀錄
    /// - Returns: 分析紀錄 DTO 清單
    func fetchAnalysisHistory() async throws -> [TremorAnalysisRecordDTO] {
        let token = try getValidToken()
        return try await apiService.fetchAnalysisHistory(token: token)
    }
}
