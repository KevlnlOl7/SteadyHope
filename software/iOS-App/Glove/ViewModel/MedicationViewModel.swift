import Combine
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class MedicationViewModel: ObservableObject {

    /// 用藥紀錄清單資料來源
    @Published var medicationList: [MedicationRecord] = []

    /// 單次紀錄表單輸入狀態（名稱、劑量數值、劑量單位、用藥時間、給藥型態與貼片部位）
    @Published var inputName: String = ""
    @Published var inputDose: String = ""
    @Published var inputUnit: String = ""
    @Published var inputDate: Date = Date()
    @Published var selectedMedType: MedicationType = .oral
    @Published var selectedPatchRegion: PatchRegion?

    /// 既有用藥紀錄編輯狀態與暫存屬性
    @Published var editingRecord: MedicationRecord?
    @Published var editName: String = ""
    @Published var editDose: String = ""
    @Published var editDate: Date = Date()
    @Published var editMedType: MedicationType = .oral
    @Published var editPatchRegion: PatchRegion?
    @Published var editingRecordID: Int? = nil

    /// 用藥資料儲存庫實體
    private let repository = MedicationRepository()

    /// 驗證單次用藥新增表單之各欄位是否皆已正確填寫
    var isAddRecordValid: Bool {
        let isNameFilled = !inputName.trimmingCharacters(in: .whitespaces).isEmpty
        let isDoseFilled = !inputDose.trimmingCharacters(in: .whitespaces).isEmpty
        let isUnitFilled = !inputUnit.trimmingCharacters(in: .whitespaces).isEmpty
        return isNameFilled && isDoseFilled && isUnitFilled
    }

    /// 從遠端伺服器載入全部用藥紀錄清單
    func loadAllRecords() async {
        do {
            let fetchedRecords = try await repository.getAllMedications(for: "")
            self.medicationList = fetchedRecords
        } catch {
            print("讀取全部紀錄失敗: \(error)")
        }
    }

    /// 依指定日期從遠端伺服器載入用藥紀錄清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd）
    func loadRecords(for date: String) async {
        do {
            let fetchedRecords = try await repository.getAllMedications(for: date)
            self.medicationList = fetchedRecords
        } catch {
            print("讀取紀錄失敗: \(error)")
        }
    }

    /// 切換口服藥物排程項目的打卡狀態（已打卡則刪除紀錄，未打卡則新增紀錄）
    /// - Parameters:
    ///   - item: 欲打卡或取消打卡之 ScheduledDoseItem 排程項目
    ///   - date: 打卡執行日期
    func toggleDoseTaken(for item: ScheduledDoseItem, on date: Date) {
        let cleanPlanName = item.plan.name.trimmingCharacters(in: .whitespaces)

        if let existingIndex = medicationList.firstIndex(where: { record in
            let nameMatch = record.name.trimmingCharacters(in: .whitespaces) == cleanPlanName
            let doseMatch = record.dose == item.plan.dose
            let typeMatch = record.medType == .oral
            let dateMatch = Calendar.current.isDate(record.date, inSameDayAs: date)
            let timeMatch = item.timeString == "未設定時間" || record.date.toString(format: "HH:mm") == item.timeString
            return nameMatch && doseMatch && typeMatch && dateMatch && timeMatch
        }) {
            let recordToDelete = medicationList[existingIndex]
            if let recordID = recordToDelete.id {
                cancelNotification(notificationID: "med_\(recordID)")
                Task {
                    do {
                        let success = try await repository.deleteMedication(id: recordID)
                        if success {
                            medicationList.remove(at: existingIndex)
                        }
                    } catch {
                        print("取消打卡失敗: \(error)")
                    }
                }
            }
        } else {
            let targetDate = combine(date: date, withTimeString: item.timeString)
            let newRecord = MedicationRecord(
                id: nil,
                userID: item.plan.userID,
                date: targetDate,
                name: cleanPlanName,
                dose: item.plan.dose,
                medType: .oral,
                patchRegion: nil
            )

            Task {
                do {
                    let success = try await repository.addMedication(newRecord)
                    if success {
                        let dateString = targetDate.toString(format: "yyyy-MM-dd")
                        await loadRecords(for: dateString)
                    }
                } catch {
                    print("口服打卡失敗: \(error)")
                }
            }
        }
    }

    /// 檢查特定口服藥物排程項目於指定日期是否已完成打卡
    /// - Parameters:
    ///   - item: 欲檢查之 ScheduledDoseItem 排程項目
    ///   - date: 目標比對日期
    /// - Returns: 已打卡回傳 true，否則回傳 false
    func isDoseTaken(for item: ScheduledDoseItem, on date: Date) -> Bool {
        let cleanPlanName = item.plan.name.trimmingCharacters(in: .whitespaces)
        return medicationList.contains { record in
            let nameMatch = record.name.trimmingCharacters(in: .whitespaces) == cleanPlanName
            let doseMatch = record.dose == item.plan.dose
            let dateMatch = Calendar.current.isDate(record.date, inSameDayAs: date)
            let timeMatch = item.timeString == "未設定時間" || record.date.toString(format: "HH:mm") == item.timeString
            return nameMatch && doseMatch && dateMatch && timeMatch
        }
    }

    /// 新增單次用藥紀錄並同步至遠端伺服器
    /// - Parameters:
    ///   - currentUserID: 使用者 ID
    ///   - token: 授權憑證字串
    func addRecord(currentUserID: Int, token: String) {
        guard isAddRecordValid else { return }

        let newRecord = MedicationRecord(
            id: nil,
            userID: currentUserID,
            date: inputDate,
            name: inputName,
            dose: "\(inputDose)\(inputUnit)",
            medType: selectedMedType,
            patchRegion: selectedPatchRegion
        )

        Task {
            do {
                let success = try await repository.addMedication(newRecord)
                if success {
                    let dateString = inputDate.toString(format: "yyyy-MM-dd")
                    await loadRecords(for: dateString)
                    scheduleNotification(for: newRecord)
                    clearInputs()
                }
            } catch {
                print("新增單次紀錄失敗: \(error)")
            }
        }
    }

    /// 載入既有用藥紀錄至編輯表單
    /// - Parameter record: 欲編輯之 MedicationRecord 實體
    func startEditingRecord(_ record: MedicationRecord) {
        self.editingRecordID = record.id
        self.inputName = record.name
        self.inputDate = record.date
        self.selectedMedType = record.medType
        self.selectedPatchRegion = record.patchRegion

        let rawDose = record.dose.trimmingCharacters(in: .whitespaces)
        if let numberMatch = rawDose.range(
            of: #"^[0-9]+(\.[0-9]+)?"#,
            options: .regularExpression
        ) {
            self.inputDose = String(rawDose[numberMatch])
            self.inputUnit = String(rawDose[numberMatch.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.inputDose = rawDose
            self.inputUnit = ""
        }
    }

    /// 儲存編輯後之用藥紀錄 (PUT /medication/:recordID)
    /// - Parameter targetDateString: 重新載入之目標日期字串（格式：yyyy-MM-dd）
    func saveEditedRecord(targetDateString: String = "") {
        guard let recordID = editingRecordID else {
            print("編輯儲存失敗: editingRecordID 為 nil")
            return
        }

        let trimmedDose = inputDose.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = inputUnit.trimmingCharacters(in: .whitespaces)
        let finalDose = trimmedUnit.isEmpty ? trimmedDose : "\(trimmedDose)\(trimmedUnit)"

        let updateDTO = UpdateMedicationRequestDTO(
            date: inputDate,
            name: inputName.trimmingCharacters(in: .whitespaces),
            dose: finalDose,
            medType: selectedMedType.rawValue,
            patchRegion: selectedPatchRegion?.rawValue,
            skinCondition: nil,
            skinImageDataList: []
        )

        Task {
            do {
                let success = try await repository.updateMedication(
                    id: recordID,
                    record: updateDTO
                )
                if success {
                    if !targetDateString.isEmpty {
                        await loadRecords(for: targetDateString)
                    } else {
                        await loadAllRecords()
                    }
                    self.editingRecordID = nil
                    self.clearInputs()
                } else {
                    print("後端回傳更新失敗")
                }
            } catch {
                print("新增單次紀錄失敗: \(error)")
            }
        }
    }

    /// 取消編輯模式並重設輸入表單與選取狀態
    func cancelEditing() {
        self.editingRecordID = nil
        clearInputs()
    }

    /// 儲存貼片用藥紀錄（包含背景圖片壓縮與後端同步）
    /// - Parameters:
    ///   - dose: 貼片劑量規格
    ///   - region: 貼片部位
    ///   - skinCondition: 貼片處皮膚狀況描述
    ///   - isCustomCondition: 是否為自訂皮膚狀況
    ///   - customCondition: 自訂皮膚狀況描述文字
    ///   - images: 患部照片圖片清單
    ///   - planUserID: 使用者 ID
    func savePatchRecord(
        dose: String,
        region: PatchRegion,
        skinCondition: String,
        isCustomCondition: Bool,
        customCondition: String,
        images: [UIImage],
        planUserID: Int
    ) {
        let finalCondition: String = {
            if isCustomCondition {
                let trimmed = customCondition.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? "其他" : trimmed
            } else {
                return skinCondition
            }
        }()

        self.selectedPatchRegion = region
        let currentDate = Date()

        Task {
            let imageDatas = await Task.detached(priority: .userInitiated) {
                images.compactMap { image -> Data? in
                    let targetWidth: CGFloat = 800
                    let finalSize: CGSize

                    if image.size.width <= targetWidth {
                        finalSize = image.size
                    } else {
                        let scale = targetWidth / image.size.width
                        finalSize = CGSize(
                            width: targetWidth,
                            height: image.size.height * scale
                        )
                    }

                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    let renderer = UIGraphicsImageRenderer(
                        size: finalSize,
                        format: format
                    )
                    let resizedImage = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: finalSize))
                    }

                    return resizedImage.jpegData(compressionQuality: 0.6)
                }
            }.value

            let apiRecord = MedicationRecord(
                id: nil,
                userID: planUserID,
                date: currentDate,
                name: "Neupro 紐普洛穿皮貼片",
                dose: dose,
                medType: .patch,
                patchRegion: region,
                skinCondition: finalCondition,
                skinImageDataList: imageDatas
            )

            do {
                let success = try await repository.addMedication(apiRecord)
                if success {
                    let dateString = currentDate.toString(format: "yyyy-MM-dd")
                    await loadRecords(for: dateString)
                }
            } catch {
                print("貼片打卡存檔失敗: \(error)")
            }
        }
    }

    /// 更新貼片用藥紀錄 (PUT /medication/:id)
    /// - Parameters:
    ///   - recordID: 欲更新之紀錄 ID
    ///   - dose: 貼片劑量規格
    ///   - originalDate: 原用藥記錄日期時間
    ///   - region: 貼片部位
    ///   - skinCondition: 皮膚狀況描述
    ///   - isCustomCondition: 是否為自訂皮膚狀況
    ///   - customCondition: 自訂皮膚狀況描述文字
    ///   - images: 患部照片圖片清單
    ///   - targetDateString: 重新載入之目標日期字串（格式：yyyy-MM-dd）
    func updatePatchRecord(
        recordID: Int,
        dose: String,
        originalDate: Date,
        region: PatchRegion,
        skinCondition: String,
        isCustomCondition: Bool,
        customCondition: String,
        images: [UIImage],
        targetDateString: String = ""
    ) {
        let finalCondition: String = {
            if isCustomCondition {
                let trimmed = customCondition.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? "其他" : trimmed
            } else {
                return skinCondition
            }
        }()

        Task {
            let imageDatas = await Task.detached(priority: .userInitiated) {
                images.compactMap { image -> Data? in
                    let targetWidth: CGFloat = 800
                    let finalSize: CGSize
                    if image.size.width <= targetWidth {
                        finalSize = image.size
                    } else {
                        let scale = targetWidth / image.size.width
                        finalSize = CGSize(width: targetWidth, height: image.size.height * scale)
                    }

                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    let renderer = UIGraphicsImageRenderer(size: finalSize, format: format)
                    let resizedImage = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: finalSize))
                    }
                    return resizedImage.jpegData(compressionQuality: 0.6)
                }
            }.value

            let updateDTO = UpdateMedicationRequestDTO(
                date: originalDate,
                name: "Neupro 紐普洛穿皮貼片",
                dose: dose,
                medType: MedicationType.patch.rawValue,
                patchRegion: region.rawValue,
                skinCondition: finalCondition,
                skinImageDataList: imageDatas
            )

            do {
                let success = try await repository.updateMedication(id: recordID, record: updateDTO)
                if success {
                    if !targetDateString.isEmpty {
                        await loadRecords(for: targetDateString)
                    } else {
                        await loadAllRecords()
                    }
                    self.editingRecord = nil
                }
            } catch {
                print("更新貼片紀錄失敗: \(error)")
            }
        }
    }

    /// 刪除指定索引集合之用藥紀錄並同步至遠端伺服器
    /// - Parameters:
    ///   - records: 當前顯示之用藥紀錄清單
    ///   - offsets: 欲刪除項目的 IndexSet 集合
    func deleteRecord(records: [MedicationRecord], at offsets: IndexSet) {
        for index in offsets {
            let recordToDelete = records[index]
            if let recordID = recordToDelete.id {
                cancelNotification(notificationID: "med_\(recordID)")
                Task {
                    do {
                        let success = try await repository.deleteMedication(id: recordID)
                        if success {
                            medicationList.removeAll { $0.id == recordID }
                        }
                    } catch {
                        print("刪除失敗: \(error)")
                    }
                }
            } else {
                medicationList.removeAll { record in
                    record.name == recordToDelete.name
                        && record.dose == recordToDelete.dose
                        && record.medType == recordToDelete.medType
                        && Calendar.current.isDate(record.date, inSameDayAs: recordToDelete.date)
                        && record.date.toString(format: "HH:mm") == recordToDelete.date.toString(format: "HH:mm")
                }
            }
        }
    }

    /// 檢查指定貼片部位在過去 14 天內是否曾被使用過
    /// - Parameter region: 欲檢查之貼片部位
    /// - Returns: 若過去 14 天內曾使用過則回傳 true，否則回傳 false
    func isRegionUsedInLast14Days(_ region: PatchRegion) -> Bool {
        let calendar = Calendar.current
        guard let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: Date()) else {
            return false
        }
        return medicationList.contains { record in
            guard record.medType == .patch,
                  record.date >= fourteenDaysAgo,
                  let recordRegion = record.patchRegion
            else {
                return false
            }
            return recordRegion == region
        }
    }

    /// 排程本機用藥推播通知
    /// - Parameter record: 目標用藥紀錄實體
    private func scheduleNotification(for record: MedicationRecord) {
        let content = UNMutableNotificationContent()
        content.title = "用藥提醒"
        content.body = "該服用/更換藥物：\(record.name) (\(record.dose))"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: record.date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let identifier: String
        if let recordID = record.id {
            identifier = "med_\(recordID)"
        } else {
            identifier = UUID().uuidString
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 取消已排程之本機用藥推播通知
    /// - Parameter notificationID: 欲取消通知之識別字串
    private func cancelNotification(notificationID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID]
        )
    }

    /// 清空單次用藥紀錄輸入表單欄位
    func clearInputs() {
        inputName = ""
        inputDose = ""
        inputUnit = ""
        inputDate = Date()
        selectedMedType = .oral
        selectedPatchRegion = nil
    }

    /// 將目標日期與時間字串合併為完整的 Date 物件
    /// - Parameters:
    ///   - date: 目標日期
    ///   - timeString: 時間字串（格式：HH:mm）
    /// - Returns: 合併後之 Date 實例
    private func combine(date: Date, withTimeString timeString: String) -> Date {
        if let timeDate = timeString.toDate(format: "HH:mm") {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: timeDate)
            let minute = calendar.component(.minute, from: timeDate)
            return calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: date
            ) ?? date
        }
        return date
    }
}
