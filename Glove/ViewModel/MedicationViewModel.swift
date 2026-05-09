import Foundation
import SwiftUI
import Combine
import SwiftData

class MedicationViewModel: ObservableObject {
    
    /// 儲存所有的用藥紀錄清單
    @Published var medicationList: [MedicationRecord] = []
    @Published var inputName: String = ""
    @Published var inputDose: String = ""
    @Published var inputUnit: String = ""
    @Published var inputDate: Date = Date()

    /// 新增用藥紀錄
    func addRecord() {
        guard !inputName.isEmpty else { return }
        
        let newRecord = MedicationRecord(
            date: inputDate,
            name: inputName,
            dose: "\(inputDose)\(inputUnit)"
        )
        
        withAnimation(.spring()) {
            medicationList.insert(newRecord, at: 0)
        }
        
        clearInputs()
    }
    
    /// 清空所有輸入欄位的內容
    func clearInputs() {
        inputName = ""
        inputDose = ""
        inputUnit = ""
        inputDate = Date()
    }
    
    /// 刪除紀錄邏輯
    /// - Parameters:
    ///   - records: 當前畫面顯示的紀錄清單
    ///   - offsets: 使用者在清單上滑動刪除的索引位置
    func deleteRecord(records: [MedicationRecord], at offsets: IndexSet) {
        for index in offsets {
            let idToDelete = records[index].id
            medicationList.removeAll { $0.id == idToDelete }
        }
    }
    
    /// 日期格式化工具
    /// - Parameters:
    ///   - date: 要轉換的 Date 物件
    ///   - format: 格式化字串
    /// - Returns: 格式化後的日期字串
    func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
