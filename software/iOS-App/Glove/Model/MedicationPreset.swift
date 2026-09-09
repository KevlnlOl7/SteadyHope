import Foundation

/// 預設藥品資料模型，封裝藥物基本資訊、規格劑量、藥理分類與劑型選項
struct PresetMedicationItem: Identifiable, Hashable {
    var id: String { "\(name)_\(strength)" }

    /// 藥品名稱
    let name: String

    /// 規格劑量
    let strength: String

    /// 藥理分類
    let category: String

    /// 給藥途徑與劑型種類（口服、貼片、注射等）
    let medType: MedicationType

    /// 介面常用服用數量選單選項清單
    let commonDoses: [String]
}

/// 預設藥品資料庫管理結構，提供系統內建之帕金森氏症常見用藥清單與篩選功能
struct MedicationPresets {
    /// 專門提供口服藥快選選單使用的藥品清單（自動過濾貼片與注射劑型）
    static var oralList: [PresetMedicationItem] {
        allList.filter { $0.medType == .oral }
    }

    /// 包含所有劑型與藥理分類的完整內建藥品庫
    static let allList: [PresetMedicationItem] = [
        // 左旋多巴複方 (Levodopa)
        PresetMedicationItem(name: "Madopar 美道普", strength: "25/100mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["半顆", "1顆", "1.5顆", "2顆"]),
        PresetMedicationItem(name: "Madopar 美道普 HBS Cap.", strength: "25/100mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["1顆", "2顆"]),
        PresetMedicationItem(name: "Madopar 美道普", strength: "50/200mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["半顆", "1顆", "1.5顆", "2顆"]),
        PresetMedicationItem(name: "Sinemet 心寧美", strength: "25/100mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["半顆", "1顆", "2顆"]),
        PresetMedicationItem(name: "Sinemet 心寧美", strength: "25/250mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Sinemet 心寧美 CR Tab.", strength: "50/200mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Numient Cap. 瑞多寧", strength: "36.25/145mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["1顆", "2顆"]),
        PresetMedicationItem(name: "Numient Cap. 瑞多寧", strength: "48.75/195mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["1顆", "2顆"]),
        PresetMedicationItem(name: "Stalevo Tab. 始立", strength: "100/25/200mg", category: "左旋多巴複方", medType: .oral, commonDoses: ["1顆"]),

        // 多巴胺促效劑 (Dopamine Agonists) - 口服
        PresetMedicationItem(name: "Requip Tab. 力必平", strength: "0.25mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆", "2顆"]),
        PresetMedicationItem(name: "Requip Tab. 力必平", strength: "1mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆", "2顆"]),
        PresetMedicationItem(name: "Requip Tab. 力必平 PD (緩釋型)", strength: "2mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Requip Tab. 力必平 PD (緩釋型)", strength: "4mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Requip Tab. 力必平 PD (緩釋型)", strength: "8mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Mirapex Tab. 樂伯克", strength: "0.25mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Mirapex Tab. 樂伯克", strength: "1mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Mirapex Tab. 樂伯克 PR (緩釋型)", strength: "0.375mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Mirapex Tab. 樂伯克 PR (緩釋型)", strength: "0.75mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Mirapex Tab. 樂伯克 PR (緩釋型)", strength: "1.5mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Butin Tab. 伯汀錠", strength: "2.5mg", category: "多巴胺促效劑", medType: .oral, commonDoses: ["半顆", "1顆"]),

        // 多巴胺促效劑 - 貼片
        PresetMedicationItem(name: "Neupro 紐普洛穿皮貼片", strength: "2mg", category: "多巴胺促效劑 (貼片)", medType: .patch, commonDoses: ["1片"]),
        PresetMedicationItem(name: "Neupro 紐普洛穿皮貼片", strength: "4mg", category: "多巴胺促效劑 (貼片)", medType: .patch, commonDoses: ["1片"]),
        PresetMedicationItem(name: "Neupro 紐普洛穿皮貼片", strength: "6mg", category: "多巴胺促效劑 (貼片)", medType: .patch, commonDoses: ["1片"]),
        PresetMedicationItem(name: "Neupro 紐普洛穿皮貼片", strength: "8mg", category: "多巴胺促效劑 (貼片)", medType: .patch, commonDoses: ["1片"]),

        // 多巴胺促效劑 - 注射
        PresetMedicationItem(name: "APO-go Pen 帕特捷筆型注射劑", strength: "10mg/ml", category: "多巴胺促效劑 (注射)", medType: .injection, commonDoses: ["1ml", "2ml"]),

        // COMT 抑制劑
        PresetMedicationItem(name: "Comtan Tab. 諾康停", strength: "200mg", category: "COMT 抑制劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Ongentys Cap. 歐健體斯", strength: "50mg", category: "COMT 抑制劑", medType: .oral, commonDoses: ["1顆"]),

        // MAO-B 抑制劑
        PresetMedicationItem(name: "Azilect Tab. 阿茲列特錠", strength: "1mg", category: "MAO-B 抑制劑", medType: .oral, commonDoses: ["1顆"]),
        PresetMedicationItem(name: "Parkryl Tab. 巴可癒", strength: "5mg", category: "MAO-B 抑制劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Eldepryl Tab. 帕定平", strength: "10mg", category: "MAO-B 抑制劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Equfina Tab. 愛可穩", strength: "50mg", category: "MAO-B 抑制劑", medType: .oral, commonDoses: ["1顆"]),

        // 麩胺酸拮抗劑
        PresetMedicationItem(name: "Amanda F.C.Tab. 安滿達膜衣錠", strength: "100mg", category: "麩胺酸拮抗劑", medType: .oral, commonDoses: ["半顆", "1顆"]),

        // 抗膽鹼劑
        PresetMedicationItem(name: "Artane Tab. 阿丹", strength: "2mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Artane Tab. 阿丹", strength: "5mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Akineton Tab. 安易能", strength: "2mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "B.H.L. Tab. 顫立靜", strength: "2mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "B.H.L. Tab. 顫立靜", strength: "5mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"]),
        PresetMedicationItem(name: "Akinfree Tab. 安汀復錠", strength: "2mg", category: "抗膽鹼劑", medType: .oral, commonDoses: ["半顆", "1顆"])
    ]
}
