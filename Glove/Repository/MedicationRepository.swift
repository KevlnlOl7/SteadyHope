import Foundation

class MedicationRepository {

    /// 底層網路服務實例
    private let apiService = MedicationService()

    /// 獲取特定日期的所有用藥紀錄
    /// - Parameter date: 查詢日期字串 (格式: yyyy-MM-dd)
    /// - Returns: 用藥紀錄陣列
    func getAllMedications(for date: String) async throws -> [MedicationRecord]
    {
        return try await apiService.fetchMedications(for: date)
    }

    /// 新增一筆用藥紀錄到伺服器
    func addMedication(_ record: MedicationRecord) async throws -> Bool {
        return try await apiService.addMedication(record: record)
    }

    /// 根據資料 ID 刪除伺服器上的紀錄
    func deleteMedication(id: Int) async throws -> Bool {
        return try await apiService.deleteMedication(id: id)
    }
}
