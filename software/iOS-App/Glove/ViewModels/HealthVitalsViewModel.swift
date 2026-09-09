import Combine
import Foundation
import SwiftUI

@MainActor
final class HealthVitalsViewModel: ObservableObject {
    @Published var vitalsList: [HealthVitalsResponseDTO] = []
    @Published var isLoading: Bool = false

    // 表單輸入狀態
    @Published var systolicBP: String = ""
    @Published var diastolicBP: String = ""
    @Published var bloodSugar: String = ""
    @Published var bodyTemp: String = ""
    @Published var bodyWeight: String = ""
    @Published var sleepHours: String = ""
    @Published var foodAmount: String = ""
    @Published var recordDate: Date = Date()

    // 編輯與彈窗控制狀態
    @Published var editingVitals: HealthVitalsResponseDTO?
    @Published var showAddVitalsSheet: Bool = false

    private let repository = HealthVitalsRepository()

    /// 依指定日期載入生理數據紀錄清單
    /// - Parameter dateString: 查詢目標日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部
    func loadVitals(for dateString: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.vitalsList = try await repository.fetchVitals(for: dateString)
        } catch {
            AppLog.error("載入生理數據失敗: \(error)")
        }
    }

    /// 儲存新增或編輯完成之生理數據紀錄至遠端伺服器
    /// - Parameter targetDateString: 操作完成後重新載入之目標日期字串
    func saveRecord(targetDateString: String) async {
        if let editing = editingVitals, let recordID = editing.id {
            // 編輯既有生理數據紀錄
            let updateDTO = UpdateHealthVitalsRequestDTO(
                date: recordDate,
                systolicBP: systolicBP.isEmpty ? nil : systolicBP,
                diastolicBP: diastolicBP.isEmpty ? nil : diastolicBP,
                bloodSugar: bloodSugar.isEmpty ? nil : bloodSugar,
                bodyTemp: bodyTemp.isEmpty ? nil : bodyTemp,
                bodyWeight: bodyWeight.isEmpty ? nil : bodyWeight,
                sleepHours: sleepHours.isEmpty ? nil : sleepHours,
                foodAmount: foodAmount.isEmpty ? nil : foodAmount
            )
            do {
                _ = try await repository.updateVitals(id: recordID, record: updateDTO)
                await loadVitals(for: targetDateString)
                clearInputs()
                editingVitals = nil
            } catch {
                AppLog.error("更新生理數據失敗: \(error)")
            }
        } else {
            // 新增生理數據紀錄
            let createDTO = CreateHealthVitalsRequestDTO(
                date: recordDate,
                systolicBP: systolicBP.isEmpty ? nil : systolicBP,
                diastolicBP: diastolicBP.isEmpty ? nil : diastolicBP,
                bloodSugar: bloodSugar.isEmpty ? nil : bloodSugar,
                bodyTemp: bodyTemp.isEmpty ? nil : bodyTemp,
                bodyWeight: bodyWeight.isEmpty ? nil : bodyWeight,
                sleepHours: sleepHours.isEmpty ? nil : sleepHours,
                foodAmount: foodAmount.isEmpty ? nil : foodAmount
            )
            do {
                _ = try await repository.addVitals(createDTO)
                await loadVitals(for: targetDateString)
                clearInputs()
                showAddVitalsSheet = false
            } catch {
                AppLog.error("新增生理數據失敗: \(error)")
            }
        }
    }

    /// 根據生理量測紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameters:
    ///   - id: 欲刪除之生理量測紀錄 ID
    ///   - targetDateString: 目標日期字串
    func deleteRecord(id: Int, targetDateString: String) async {
        do {
            let success = try await repository.deleteVitals(id: id)
            if success {
                vitalsList.removeAll { $0.id == id }
            }
        } catch {
            AppLog.error("刪除生理數據失敗: \(error)")
        }
    }

    /// 載入既有生理數據資料至編輯表單狀態
    /// - Parameter item: 欲編輯之 HealthVitalsResponseDTO 實例
    func startEditing(_ item: HealthVitalsResponseDTO) {
        self.editingVitals = item
        self.recordDate = item.date
        self.systolicBP = item.systolicBP ?? ""
        self.diastolicBP = item.diastolicBP ?? ""
        self.bloodSugar = item.bloodSugar ?? ""
        self.bodyTemp = item.bodyTemp ?? ""
        self.bodyWeight = item.bodyWeight ?? ""
        self.sleepHours = item.sleepHours ?? ""
        self.foodAmount = item.foodAmount ?? ""
    }

    /// 清空生理數據表單輸入欄位與重設量測時間
    func clearInputs() {
        systolicBP = ""
        diastolicBP = ""
        bloodSugar = ""
        bodyTemp = ""
        bodyWeight = ""
        sleepHours = ""
        foodAmount = ""
        recordDate = Date()
    }
}
