import SwiftUI

struct VersionSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

struct VersionItem: Identifiable {
    let id = UUID()
    let version: String
    let releaseDate: String
    let isLatest: Bool
    let sections: [VersionSection]
}

struct VersionHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let history: [VersionItem] = [
        VersionItem(
            version: "1.0.0",
            releaseDate: "2026 年 9 月",
            isLatest: true,
            sections: [
                VersionSection(
                    title: "智慧硬體與震顫分析",
                    items: [
                        "支援低功耗藍牙手套連線、電量偵測與馬達抑震狀態監控",
                        "即時運算 RMS 震動強度與 PSD 頻率特徵圖表",
                        "手套機械長度微調控制（-5cm 至 +5cm）",
                        "顯著震顫事件智慧捕捉與情境標籤歸檔"
                    ]
                ),
                VersionSection(
                    title: "處方排程與日常健康",
                    items: [
                        "常規處方多時段排程與服藥一鍵打卡推播",
                        "貼片用藥 14 天內已使用部位提醒、膚況記錄與 30 秒按壓引導",
                        "日常表徵影音記錄牆（最多支援 5 張照片）",
                        "記錄血壓、血糖、體溫、體重、睡眠與飲食等生理徵象"
                    ]
                ),
                VersionSection(
                    title: "自我量表與家庭照護",
                    items: [
                        "動作障礙自我評估（1 分鐘快篩、主題篩檢與 25 題每週量表）",
                        "病患與照護者 6 位數安全配對碼連動與細部權限管理",
                        "家庭心情留言板（最多可輸入 100 字、患者身份心情與留言選填與照護者身份私密留言）"
                    ]
                ),
                VersionSection(
                    title: "AI 諮詢與醫療報告",
                    items: [
                        "AI 衛教對話室（支援文字與日曆檢索）",
                        "回診溝通卡片雙步驟自動萃取就診摘要",
                        "一鍵匯出 PDF 報告（內嵌連續走勢圖與頻譜圖）"
                    ]
                )
            ]
        )
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(history) { item in
                    versionCard(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("版本紀錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func versionCard(_ item: VersionItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Text("Version \(item.version)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                if item.isLatest {
                    Text("最新")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(item.releaseDate)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(item.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        ForEach(section.items, id: \.self) { change in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(AppTheme.textSecondary(for: colorScheme).opacity(0.45))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)

                                Text(change)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(14)
    }
}
