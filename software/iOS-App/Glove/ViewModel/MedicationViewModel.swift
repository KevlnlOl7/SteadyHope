import Combine
import Foundation
import SwiftData
import SwiftUI

class MedicationViewModel: ObservableObject {

    /// 儲存所有的用藥紀錄清單
    @Published var medicationList: [MedicationRecord] = []
    @Published var inputName: String = ""
    @Published var inputDose: String = ""
    @Published var inputUnit: String = ""
    @Published var inputDate: Date = Date()

    private let repository = MedicationRepository()

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

    /// 載入特定日期的用藥紀錄
    /// - Parameter date: 格式為 yyyy-MM-dd 的字串
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

    /// 新增用藥紀錄
    /// - Parameter currentUserID: 傳入目前登入使用者的 ID (來自 loginVM.userData)
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
                // 這裡可以選擇是否把 token 傳入 repository，
                // 或者維持現狀，但至少讓 ViewModel 知道現在是有 token 的狀態
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

    /// 刪除紀錄邏輯
    /// - Parameters:
    ///   - records: 當前畫面顯示的紀錄清單
    ///   - offsets: 使用者在清單上滑動刪除的索引位置
    func deleteRecord(records: [MedicationRecord], at offsets: IndexSet) {
        for index in offsets {
            let recordToDelete = records[index]

            // 確保有 id 才能在後端刪除
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

    func clearInputs() {
        inputName = ""
        inputDose = ""
        inputUnit = ""
        inputDate = Date()
    }
}
