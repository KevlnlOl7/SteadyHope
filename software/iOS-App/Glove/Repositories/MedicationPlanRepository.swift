import Foundation

class MedicationPlanRepository {
    private let apiService = MedicationPlanAPIService()

    /// 取得所有用藥排程清單
    /// - Returns: 轉換完成之 MedicationPlan 領域模型陣列
    /// - Throws: 網路請求失敗或資料解碼異常時拋出錯誤
    func getAllPlans() async throws -> [MedicationPlan] {
        let dtos = try await apiService.fetchAllPlans()
        return dtos.map { $0.toModel() }
    }

    /// 新增或儲存用藥排程
    /// - Parameter plan: 欲儲存之 MedicationPlan 領域模型實例
    /// - Returns: 儲存成功回傳 true，否則回傳 false
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func savePlan(_ plan: MedicationPlan) async throws -> Bool {
        let dto = plan.toDTO()
        return try await apiService.savePlan(plan: dto)
    }

    /// 根據用藥計畫 ID 刪除遠端伺服器上的排程
    /// - Parameter id: 欲刪除之用藥計畫 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func deletePlan(id: Int) async throws -> Bool {
        try await apiService.deletePlan(id: id)
    }
}
