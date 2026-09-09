import Combine
import Foundation
import SwiftUI

@MainActor
final class SymptomViewModel: ObservableObject {
    @Published var symptomList: [SymptomRecord] = []

    // 新增症狀紀錄狀態
    @Published var symptomNote: String = ""
    @Published var isVideoMedia: Bool = false

    // 編輯症狀紀錄狀態
    @Published var editSymptomNote: String = ""
    @Published var editTempImages: [UIImage] = []
    @Published var editingSymptomItem: SymptomRecord?

    /// 紀錄背景處理中之症狀紀錄 ID 集合（供畫面局部載入指示器使用）
    @Published var processingIDs: Set<Int> = []

    /// 初始載入或切換日期時之資料讀取狀態
    @Published var isFetchingData: Bool = false

    private let symptomRepository = SymptomRepository()

    /// 依指定日期從遠端伺服器載入症狀紀錄清單
    /// - Parameters:
    ///   - date: 查詢日期字串（格式：yyyy-MM-dd），預設為空字串查詢全部
    ///   - isSilent: 是否以靜默模式載入（為 true 時不觸發全螢幕載入指示器）
    func loadSymptoms(for date: String = "", isSilent: Bool = false) async {
        if !isSilent {
            isFetchingData = true
        }

        defer {
            if !isSilent {
                isFetchingData = false
            }
        }

        do {
            let fetchedSymptoms = try await symptomRepository.getAllSymptoms(for: date)
            let uploadingItems = symptomList.filter { ($0.id ?? 0) < 0 }
            symptomList = uploadingItems + fetchedSymptoms
        } catch {
            print("讀取症狀紀錄失敗: \(error.localizedDescription)")
        }
    }

    /// 檢查新增症狀紀錄表單輸入是否有效
    /// - Parameter tempImagesCount: 暫存照片選擇數量
    /// - Returns: 若包含圖片或文字描述不為空則回傳 true，否則回傳 false
    func isAddSymptomValid(tempImagesCount: Int) -> Bool {
        tempImagesCount > 0 || !symptomNote.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 新增症狀紀錄並採用樂觀更新策略同步至遠端伺服器
    /// - Parameters:
    ///   - currentUserID: 使用者 ID
    ///   - images: 症狀照片圖片清單
    ///   - date: 症狀發生日期時間
    func addSymptomRecord(
        currentUserID: Int,
        images: [UIImage] = [],
        date: Date
    ) {
        guard !symptomNote.isEmpty || !images.isEmpty else { return }

        // 產生暫時的負數 ID 代表此項目為本機暫存
        let tempID = -Int.random(in: 1...999999)
        processingIDs.insert(tempID)

        let noteToSave = symptomNote
        let isVideoToSave = isVideoMedia
        clearSymptomInputs()

        Task {
            // 背景執行圖片 JPEG 壓縮轉檔
            let imageDatas = await Task.detached(priority: .userInitiated) {
                images.compactMap { $0.jpegData(compressionQuality: 0.8) }
            }.value

            // 建立帶有暫時 ID 之本機症狀紀錄實體
            let tempSymptom = SymptomRecord(
                id: tempID,
                userID: currentUserID,
                date: date,
                symptomNote: noteToSave,
                mediaDataList: imageDatas,
                isVideo: isVideoToSave
            )

            // 樂觀更新：直接插入畫面首筆以提供即時反饋
            symptomList.insert(tempSymptom, at: 0)

            // 建立發送至伺服器之正式資料實體（ID 設為 nil 交由伺服器生成）
            let symptomForAPI = SymptomRecord(
                id: nil,
                userID: currentUserID,
                date: date,
                symptomNote: noteToSave,
                mediaDataList: imageDatas,
                isVideo: isVideoToSave
            )

            do {
                let success = try await symptomRepository.addSymptom(symptomForAPI)
                if success {
                    await loadSymptoms(for: date.toString(format: "yyyy-MM-dd"), isSilent: true)
                }
            } catch {
                print("新增症狀紀錄失敗: \(error.localizedDescription)")
            }

            // 處理完成後移除暫存項目與標記
            symptomList.removeAll { $0.id == tempID }
            processingIDs.remove(tempID)
        }
    }

    /// 載入既有症狀紀錄至編輯表單
    /// - Parameter item: 欲編輯之 SymptomRecord 實例
    func startEditing(_ item: SymptomRecord) {
        editSymptomNote = item.symptomNote
        editTempImages = item.mediaDataList.compactMap { UIImage(data: $0) }
        editingSymptomItem = item
    }

    /// 儲存編輯後之症狀紀錄並同步至遠端伺服器 (PUT /symptom/:recordID)
    func saveEditedSymptom(originalItem: SymptomRecord) {
        guard let recordID = originalItem.id else { return }
        processingIDs.insert(recordID)

        let noteToSave = editSymptomNote
        let originalDate = originalItem.date
        let isVideo = originalItem.isVideo

        Task {
            // 背景執行圖片 JPEG 壓縮轉檔
            let updatedDatas = await Task.detached(priority: .userInitiated) { [editTempImages] in
                editTempImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
            }.value

            let updatedSymptom = SymptomRecord(
                id: recordID,
                userID: originalItem.userID,
                date: originalDate,
                symptomNote: noteToSave,
                mediaDataList: updatedDatas,
                isVideo: isVideo
            )

            // 樂觀更新：直接替換本機畫面資料
            if let index = symptomList.firstIndex(where: { $0.id == recordID }) {
                symptomList[index] = updatedSymptom
            }
            editingSymptomItem = nil

            let updateDTO = UpdateSymptomRequestDTO(
                date: originalDate,
                symptomNote: noteToSave,
                mediaDataList: updatedDatas,
                isVideo: isVideo
            )

            do {
                let success = try await symptomRepository.updateSymptom(
                    id: recordID,
                    record: updateDTO
                )
                if success {
                    await loadSymptoms(
                        for: originalDate.toString(format: "yyyy-MM-dd"),
                        isSilent: true
                    )
                }
            } catch {
                print("更新症狀紀錄失敗: \(error)")
            }

            processingIDs.remove(recordID)
        }
    }

    /// 刪除指定之症狀紀錄並同步至遠端伺服器
    /// - Parameter item: 欲刪除之 SymptomRecord 實例
    func deleteSymptom(_ item: SymptomRecord) {
        guard let recordID = item.id else {
            symptomList.removeAll { $0.id == item.id }
            return
        }

        processingIDs.insert(recordID)

        Task {
            do {
                let success = try await symptomRepository.deleteSymptom(id: recordID)
                if success {
                    symptomList.removeAll { $0.id == recordID }
                }
            } catch {
                print("刪除症狀紀錄失敗: \(error)")
            }

            processingIDs.remove(recordID)
        }
    }

    /// 清空新增症狀表單輸入狀態
    func clearSymptomInputs() {
        symptomNote = ""
        isVideoMedia = false
    }
}
