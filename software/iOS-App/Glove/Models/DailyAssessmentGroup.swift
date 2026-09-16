import Foundation

/// 依日期分組的歷史紀錄結構
struct DailyAssessmentGroup: Identifiable, Equatable {
    let id: String
    let dateText: String 
    var records: [DailyAssessmentResponseDTO]
}
