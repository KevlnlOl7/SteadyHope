import Foundation

/// 網路請求與 API 通訊相關之標準錯誤定義
public enum NetworkError: LocalizedError, Sendable {
    case invalidURL
    case encodingFailed
    case decodeError
    case noData
    case unauthorized
    case serverError(reason: String)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無效的 URL 路徑"
        case .encodingFailed:
            return "資料編碼為 JSON 失敗"
        case .decodeError:
            return "資料解析 (Decode) 失敗"
        case .noData:
            return "伺服器未回傳有效資料"
        case .unauthorized:
            return "未授權 (401)，請檢查 Token"
        case .serverError(let reason):
            return "伺服器錯誤: \(reason)"
        case .unknown(let error):
            return "未知錯誤: \(error.localizedDescription)"
        }
    }
}
