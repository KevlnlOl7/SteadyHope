import Foundation

protocol TremorAPIServiceProtocol {
    /// 上傳壓縮之原始震顫取樣數據
    func uploadRawData(_ payload: TremorRawUploadRequestDTO, token: String) async throws

    /// 上傳單筆震顫分析特徵紀錄
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO, token: String) async throws

    /// 取得歷史原始震顫取樣二進位壓縮封包清單
    func fetchRawDataHistory(token: String) async throws -> [RawTremorDataDTO]

    /// 取得歷史震顫分析特徵紀錄清單
    func fetchAnalysisHistory(token: String) async throws -> [TremorAnalysisRecordDTO]
}

/// 震顫後端 API 傳輸服務實作，負責 HTTP 請求組裝、驗證標頭設定、狀態碼檢查與 JSON 解析
final class TremorAPIService: TremorAPIServiceProtocol {

    /// 全域單例存取點
    static let shared = TremorAPIService()

    /// 震顫相關端點之基礎 URL 路徑
    private var baseURL: String {
        var base = APIConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return "\(base)/tremor"
    }

    /// 初始化實體
    init() {}

    /// 建立具備統一日期與鍵值解碼策略的 JSONDecoder 實體
    /// - Parameter useSnakeCase: 是否將蛇形命名轉換為駝峰命名，預設為 true
    /// - Returns: 設定完成的 JSONDecoder
    private func makeDecoder(useSnakeCase: Bool = true) -> JSONDecoder {
        let decoder = JSONDecoder()
        if useSnakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 上傳壓縮之原始震顫取樣數據至伺服器
    /// - Parameters:
    ///   - payload: 封裝壓縮數據之請求 DTO
    ///   - token: 身分驗證 Bearer 權杖
    func uploadRawData(_ payload: TremorRawUploadRequestDTO, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/raw") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 上傳單筆震顫特徵分析紀錄至伺服器
    /// - Parameters:
    ///   - record: 震顫分析特徵資料 DTO
    ///   - token: 身分驗證 Bearer 權杖
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/analysis") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            request.httpBody = try encoder.encode(record)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 向伺服器拉取所有歷史原始震顫數據封包
    /// - Parameter token: 身分驗證 Bearer 權杖
    /// - Returns: 歷史原始震顫數據 DTO 陣列
    func fetchRawDataHistory(token: String) async throws -> [RawTremorDataDTO] {
        guard let url = URL(string: "\(baseURL)/raw") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 向伺服器拉取所有歷史震顫分析特徵紀錄
    /// - Parameter token: 身分驗證 Bearer 權杖
    /// - Returns: 歷史震顫分析紀錄 DTO 陣列
    func fetchAnalysisHistory(token: String) async throws -> [TremorAnalysisRecordDTO] {
        guard let url = URL(string: "\(baseURL)/history") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }
}
