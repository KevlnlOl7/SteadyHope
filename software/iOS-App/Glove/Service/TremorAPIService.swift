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

    /// 檢查 HTTP 回應狀態碼，特別攔截 401 權限失效並發送系統通知
    /// - Parameters:
    ///   - httpResponse: HTTP 伺服器回應實體
    ///   - data: 伺服器回傳之二進位內容
    private func checkStatusCode(_ httpResponse: HTTPURLResponse, data: Data) throws {
        if httpResponse.statusCode == 401 {
            let reason = parseServerError(data: data, code: 401)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .didReceive401Unauthorized,
                    object: nil,
                    userInfo: ["message": reason]
                )
            }
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 解析後端 Vapor 伺服器回傳之錯誤訊息 JSON
    /// - Parameters:
    ///   - data: 伺服器回傳之錯誤訊息二進位內容
    ///   - code: HTTP 狀態碼
    /// - Returns: 格式化後之錯誤原因描述文字
    private func parseServerError(data: Data, code: Int) -> String {
        struct VaporError: Decodable {
            let reason: String
        }
        if let serverError = try? JSONDecoder().decode(VaporError.self, from: data) {
            return serverError.reason
        }
        return "連線失敗，錯誤碼：\(code)"
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
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(
                reason: parseServerError(data: data, code: httpResponse.statusCode)
            )
        }
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
        request.httpBody = try encoder.encode(record)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(
                reason: parseServerError(data: data, code: httpResponse.statusCode)
            )
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(
                reason: parseServerError(data: data, code: httpResponse.statusCode)
            )
        }

        return try makeDecoder().decode([RawTremorDataDTO].self, from: data)
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(
                reason: parseServerError(data: data, code: httpResponse.statusCode)
            )
        }

        return try makeDecoder().decode([TremorAnalysisRecordDTO].self, from: data)
    }
}
