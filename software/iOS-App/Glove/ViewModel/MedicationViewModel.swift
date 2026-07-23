import Combine
import Foundation
import SwiftData
import SwiftUI

class MedicationViewModel: ObservableObject {

    /// 儲存當前載入的用藥紀錄清單
    @Published var medicationList: [MedicationRecord] = []
    @Published var inputName: String = ""
    @Published var inputDose: String = ""
    @Published var inputUnit: String = ""
    @Published var inputDate: Date = Date()

    /// 睡眠小時數
    @Published var inputSleepHours: String = ""
    
    /// 食量狀況
    @Published var inputFoodAmount: String = ""
    
    /// 收縮壓 (mmHg)
    @Published var inputSystolicBP: String = ""
    
    /// 舒張壓 (mmHg)
    @Published var inputDiastolicBP: String = ""
    
    /// 血糖濃度
    @Published var inputBloodSugar: String = ""
    
    /// 體溫 (°C)
    @Published var inputBodyTemp: String = ""
    
    /// 體重 (kg)
    @Published var inputBodyWeight: String = ""

    /// 資料存取 Repository 層實例
    private let repository = MedicationRepository()

    /// 載入資料庫或伺服器內所有的用藥歷史紀錄
    @MainActor
    func loadAllRecords() async {
        print("--- 開始載入所有歷史紀錄 ---")
        do {
            let fetchedRecords = try await repository.getAllMedications(for: "")
            self.medicationList = fetchedRecords
        } catch {
            print("讀取全部紀錄失敗: \(error)")
        }
    }

    /// 載入指定日期的用藥紀錄
    /// - Parameter date: 日期字串 (格式: yyyy-MM-dd)
    @MainActor
    func loadRecords(for date: String) async {
        do {
            let fetchedRecords = try await repository.getAllMedications(
                for: date
            )
            self.medicationList = fetchedRecords
        } catch {
            print("讀取紀錄失敗: \(error)")
        }
    }

    /// 新增用藥紀錄並更新伺服器與本地畫面
    /// - Parameters:
    ///   - currentUserID: 當前登入使用者的識別 ID
    ///   - token: 使用者驗證 Token
    func addRecord(currentUserID: Int, token: String) {
        guard !inputName.isEmpty else { return }

        let newRecord = MedicationRecord(
            id: nil,
            userID: currentUserID,
            date: inputDate,
            name: inputName,
            dose: "\(inputDose)\(inputUnit)"
        )

        Task {
            do {
                let success = try await repository.addMedication(newRecord)

                if success {
                    let dateString = inputDate.toString(format: "yyyy-MM-dd")
                    await loadRecords(for: dateString)
                    await MainActor.run { clearInputs() }
                }
            } catch {
                print("新增失敗: \(error)")
            }
        }
    }

    /// 刪除指定索引位置的用藥紀錄
    /// - Parameters:
    ///   - records: 當前畫面展示的紀錄清單
    ///   - offsets: 滑動刪除動作產生的索引集合
    func deleteRecord(records: [MedicationRecord], at offsets: IndexSet) {
        for index in offsets {
            let recordToDelete = records[index]

            // 確保含有唯一識別 ID 才能呼叫後端 API 進行刪除
            if let id = recordToDelete.id {
                Task {
                    do {
                        let success = try await repository.deleteMedication(
                            id: id
                        )
                        if success {
                            await MainActor.run {
                                medicationList.removeAll { $0.id == id }
                            }
                        }
                    } catch {
                        print("刪除失敗: \(error)")
                    }
                }
            }
        }
    }

    /// 重置輸入表單資料為預設初始值
    func clearInputs() {
        inputName = ""
        inputDose = ""
        inputUnit = ""
        inputDate = Date()
        inputSleepHours = ""
        inputFoodAmount = ""
        inputSystolicBP = ""
        inputDiastolicBP = ""
        inputBloodSugar = ""
        inputBodyTemp = ""
        inputBodyWeight = ""
    }
}
