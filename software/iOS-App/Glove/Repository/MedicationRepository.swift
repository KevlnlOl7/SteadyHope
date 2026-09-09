import Foundation

class MedicationRepository {

    /// 底層網路服務實例
    private let apiService = MedicationService()

    /// 獲取特定日期的所有用藥紀錄
    /// - Parameter date: 查詢日期字串 (格式: yyyy-MM-dd)
    /// - Returns: 用藥紀錄陣列（包含從 DTO 轉換後的 MedicationRecord 模型）
    /// - Throws: 網路請求或解析失敗時拋出錯誤
    func getAllMedications(for date: String) async throws -> [MedicationRecord]
    {
        // 呼叫 Service 取得 API 回傳的 DTO 陣列
        let dtos = try await apiService.fetchMedications(for: date)
        
        // 將 DTO 陣列轉化為 UI 與 SwiftData 應用的 MedicationRecord 模型陣列
        return dtos.map { $0.toModel() }
    }

    /// 新增一筆用藥紀錄到伺服器
    /// - Parameter record: 待新增的 MedicationRecord 模型
    /// - Returns: 新增成功與否之布林值
    /// - Throws: 網路請求失敗時拋出錯誤
    func addMedication(_ record: MedicationRecord) async throws -> Bool {
        // 將 Model 轉換為 DTO 後交由 Service 送出
        let dto = record.toDTO()
        return try await apiService.addMedication(record: dto)
    }

    /// 根據資料 ID 刪除伺服器上的紀錄
    /// - Parameter id: 用藥紀錄之唯一識別 ID
    /// - Returns: 刪除成功與否之布林值
    /// - Throws: 網路請求失敗時拋出錯誤
    func deleteMedication(id: Int) async throws -> Bool {
        return try await apiService.deleteMedication(id: id)
    }
    
    /// 更新指定用藥紀錄並同步至遠端伺服器
    /// - Parameters:
    ///   - id: 欲更新之用藥紀錄 ID
    ///   - record: 包含更新內容之 UpdateMedicationRequestDTO 實體
    /// - Returns: 更新成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出錯誤
    func updateMedication(id: Int, record: UpdateMedicationRequestDTO) async throws -> Bool {
        try await apiService.updateMedication(id: id, record: record)
    }
}
