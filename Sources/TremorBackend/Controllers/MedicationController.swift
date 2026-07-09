import Fluent
import Vapor

struct MedicationController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // 同樣放在受 JWT 保護的群組下
        let meds = routes.grouped("medication")
        meds.post("add", use: addRecord)
        meds.get("search", use: getRecordsByDate)
        // 新增：刪除路由，使用動態路徑傳遞要刪除的 ID
        // 接口：DELETE /medication/:recordID
        meds.delete(":recordID", use: deleteRecord)
    }
    
    // 1. 儲存用藥紀錄
    @Sendable
    func addRecord(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        
        // 建立一個局部的 Decoder，只在這裡使用 ISO8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        struct AddMedRequest: Content {
            let date: Date
            let name: String
            let dose: String
        }
        
        // 指定使用剛才建立的 decoder 來解析內容
        let data = try req.content.decode(AddMedRequest.self, using: decoder)
        
        let record = MedicationRecord(
            userID: payload.userID,
            date: data.date,
            name: data.name,
            dose: data.dose
        )
        
        try await record.save(on: req.db)
        return .ok
    }
    
    // 2. 按日期查詢
    @Sendable
    func getRecordsByDate(req: Request) async throws -> Response { // 改回傳 Response 物件
        let payload = try req.auth.require(UserPayload.self)
        
        guard let searchDateString = req.query[String.self, at: "date"] else {
            throw Abort(.badRequest, reason: "請提供查詢日期")
        }
        
        // 這裡維持用 yyyy-MM-dd 解析「搜尋參數」，因為搜尋通常只給日期
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dayStart = formatter.date(from: searchDateString) else {
            throw Abort(.badRequest, reason: "日期格式錯誤，請使用 yyyy-MM-dd")
        }
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)
        
        // 查詢當天所有紀錄
        let records = try await MedicationRecord.query(on: req.db)
            .filter(\.$userID == payload.userID)
            .filter(\.$date >= dayStart)
            .filter(\.$date < dayEnd)
            .sort(\.$date, .ascending)
            .all()
        
        // 關鍵點：手動建立帶有 ISO8601 策略的 Encoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let body = try encoder.encode(records)
        
        // 組裝回傳內容，並指定為 application/json
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(data: body)
        )
    }
    // 3. 刪除用藥紀錄
    @Sendable
    func deleteRecord(req: Request) async throws -> HTTPStatus {
        // 安全檢查：獲取當前登入者資訊
        let payload = try req.auth.require(UserPayload.self)
        
        // 從網址路徑中取得 recordID 並轉為 Int
        guard let recordID = req.parameters.get("recordID", as: Int.self) else {
            throw Abort(.badRequest, reason: "無效的紀錄 ID")
        }
        
        // 查詢邏輯：
        // 1. 根據 recordID 查找
        // 2. 必須滿足 userID == payload.userID (防止刪到別人的資料)
        guard let record = try await MedicationRecord.query(on: req.db)
            .filter(\.$id == recordID)
            .filter(\.$userID == payload.userID)
            .first() else {
            throw Abort(.notFound, reason: "找不到該筆紀錄或無權限刪除")
        }
        
        // 執行刪除
        try await record.delete(on: req.db)
        
        return .noContent // 204 No Content 代表刪除成功且無須回傳資料
    }
}






