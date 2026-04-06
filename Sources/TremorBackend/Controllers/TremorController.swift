import Fluent
import Vapor

struct TremorController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let tremor = routes.grouped("tremor")
        tremor.post("data", use: uploadData)
        // 使用路徑參數 :userID 讓 App 指定要看誰的資料
        tremor.get("history", ":userID", use: getHistory)
    }

    @Sendable
    func uploadData(req: Request) async throws -> HTTPStatus {
        struct TremorUploadRequest: Content {
            let userID: Int
            let accX: Double
            let accY: Double
            let accZ: Double
            let gyroX: Double
            let gyroY: Double
            let gyroZ: Double
        }

        let data = try req.content.decode(TremorUploadRequest.self)
        let record = TremorData(
            userID: data.userID,
            accX: data.accX,
            accY: data.accY,
            accZ: data.accZ,
            gyroX: data.gyroX,
            gyroY: data.gyroY,
            gyroZ: data.gyroZ
        )

        try await record.save(on: req.db)
        return .ok
    }
    @Sendable
    func getHistory(req: Request) async throws -> [TremorData] {
        // 從網址中取得 userID
        guard let userIDString = req.parameters.get("userID"),
            let userID = Int(userIDString)
        else {
            throw Abort(.badRequest, reason: "無效的使用者 ID")
        }

        // 從資料庫搜尋該使用者的所有紀錄，並依照時間由新到舊排序
        return try await TremorData.query(on: req.db)
            .filter(\.$userID == userID)
            .sort(\.$timestamp, .descending)  // 時間最晚的排前面
            .all()
    }
}
