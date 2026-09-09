import Foundation

protocol TremorRepositoryProtocol {
    /// 透過 TremorEvent 同步 400 筆原始 IMU 數據（以 event.timestamp 作為基準時間）
    func syncRawEventData(event: TremorEvent, sessionId: String) async throws

    /// 上傳與同步原始 IMU 數據（baseDate 代表 rawPoints 第一筆 sample 的絕對時間）
    func syncRawData(sessionId: String, rawPoints: [TremorDataPoint], baseDate: Date) async throws

    /// 同步單筆震顫分析紀錄至伺服器
    func syncAnalysisResult(record: TremorAnalysisRecordDTO) async throws

    /// 將震顫事件物件轉換並同步至分析紀錄資料表
    func syncEventAsAnalysisRecord(event: TremorEvent, sessionId: String) async throws

    /// 批次同步震顫事件陣列至資料庫
    func syncBatchEvents(_ events: [TremorEvent], sessionId: String) async throws

    /// 取得歷史原始 IMU 數據點（相容舊介面，不含絕對時間資訊）
    func fetchRawDataHistory() async throws -> [TremorDataPoint]

    /// 取得歷史原始 IMU 數據，經二進位解壓縮後保留每一筆取樣點之精確 recordedAt 時間戳記
    func fetchTimedRawDataHistory() async throws -> [TremorTimedRawPoint]

    /// 取得伺服器端歷史分析紀錄 DTO 列表
    func fetchAnalysisHistory() async throws -> [TremorAnalysisRecordDTO]
}

/// 震顫資料儲存庫實作類別，負責管理身分驗證權杖、執行二進位 zlib 壓縮演算法及串接後端 API 服務
final class TremorRepository: TremorRepositoryProtocol {

    /// 網路 API 傳輸服務實體
    private let apiService: TremorAPIServiceProtocol

    /// 身分驗證權杖取得閉包
    private let tokenProvider: () -> String?

    /// 初始化震顫儲存庫實體
    /// - Parameters:
    ///   - apiService: 震顫 API 服務實體，預設為單例實體
    ///   - tokenProvider: 取得身分驗證權杖之閉包，預設向 AuthManager 查詢
    init(
        apiService: TremorAPIServiceProtocol = TremorAPIService.shared,
        tokenProvider: @escaping () -> String? = { AuthManager.shared.getToken() }
    ) {
        self.apiService = apiService
        self.tokenProvider = tokenProvider
    }

    /// 檢查並取得當前合法之身分驗證權杖
    /// - Returns: 有效的權杖字串
    /// - Throws: 若權杖不存在或為空則拋出未授權錯誤
    private func getValidToken() throws -> String {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NetworkError.unauthorized
        }
        return token
    }

    /// 透過震顫事件模型同步視窗原始取樣，以事件發生時間戳記作為視窗基準起點
    /// - Parameters:
    ///   - event: 震顫事件模型實體
    ///   - sessionId: 量測工作階段識別碼
    func syncRawEventData(event: TremorEvent, sessionId: String) async throws {
        try await syncRawData(
            sessionId: sessionId,
            rawPoints: event.rawWindowData,
            baseDate: event.timestamp
        )
    }

    /// 核心壓縮與上傳流程：計算相對時間偏移並寫入絕對時間戳記，轉為 JSON 後施以 zlib 壓縮上傳
    /// - Parameters:
    ///   - sessionId: 量測工作階段識別碼
    ///   - rawPoints: 待上傳之原始取樣數據點陣列
    ///   - baseDate: 批次數據第一筆取樣點對應之基準絕對時間，預設為當前時刻
    func syncRawData(
        sessionId: String,
        rawPoints: [TremorDataPoint],
        baseDate: Date = Date()
    ) async throws {
        guard !rawPoints.isEmpty else { return }

        let token = try getValidToken()
        let firstTick = rawPoints.first?.sampleTickMs ?? 0

        let dtos = rawPoints.enumerated().map { index, point in
            let offsetMs: Double
            if point.sampleTickMs >= firstTick {
                offsetMs = Double(point.sampleTickMs - firstTick)
            } else {
                // 硬體 tick 發生溢位回繞時，依資料序號與 50 Hz 預期間隔（20 ms）推算時間補償
                offsetMs = Double(index * 20)
            }

            let pointDate = baseDate.addingTimeInterval(offsetMs / 1000.0)

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

    /// 上傳單筆震顫特徵分析結果至後端
    /// - Parameter record: 震顫分析紀錄資料傳輸物件
    func syncAnalysisResult(record: TremorAnalysisRecordDTO) async throws {
        let token = try getValidToken()
        try await apiService.uploadAnalysisRecord(record, token: token)
    }

    /// 將本地震顫事件轉換為標準分析紀錄 DTO 並同步上傳至後端伺服器
    /// - Parameters:
    ///   - event: 本地顯著震顫事件模型
    ///   - sessionId: 關聯之量測會話識別碼
    func syncEventAsAnalysisRecord(event: TremorEvent, sessionId: String) async throws {
        let recordDTO = TremorAnalysisRecordDTO(
            id: event.id,
            sessionId: sessionId,
            recordedAt: event.timestamp,
            dominantFrequencyHz: event.dominantFrequency > 0 ? event.dominantFrequency : nil,
            tremorStrengthRmsDps: event.rmsValue,
            motorOnFraction: event.isMotorActive ? 1.0 : 0.0,
            dataValid: true,
            frequencyReliable: true,
            activityTag: event.userTag.isEmpty ? "未標記" : event.userTag,
            note: nil
        )
        try await syncAnalysisResult(record: recordDTO)
    }

    /// 循序批次同步多筆震顫事件至伺服器端
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
            guard let decompressedDTOs = try? rawDTO.decompressPoints() else {
                continue
            }

            allPoints.append(contentsOf: decompressedDTOs.map { dto in
                TremorTimedRawPoint(
                    timestamp: dto.recordedAt,
                    point: TremorDataPoint(
                        sequence: dto.sequence,
                        sampleTickMs: dto.sampleTickMs,
                        gyroXDps: dto.gyroXDps,
                        gyroYDps: dto.gyroYDps,
                        gyroZDps: dto.gyroZDps,
                        sensorValid: dto.sensorValid,
                        motorEnabled: dto.motorEnabled
                    )
                )
            })
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
