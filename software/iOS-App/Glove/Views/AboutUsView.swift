import Foundation
import SwiftUI

struct AboutUsView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                headerSection
                versionCard
                introCard
                featuresCard
                disclaimerCard
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("關於我們")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("SteadyHopeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 4) {
                Text("SteadyHope")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("智慧震顫追蹤與遠距照護輔助系統")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var versionCard: some View {
        NavigationLink(destination: VersionHistoryView()) {
            HStack {
                Text("版本紀錄")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("v\(AppConfig.appVersion)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
        .modifier(CardModifier())
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("系統簡介")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            Text("SteadyHope 是專為動作障礙患者及其家庭照護者打造的智慧遠距健康管理系統。透過穿戴式手套與行動端應用程式的整合，將傳統仰賴主觀陳述的發作表徵轉化為客觀的連續數據。\n\n系統整合低功耗藍牙傳輸、主動抑震致動、連續震顫強度（RMS）與頻譜（PSD）特徵運算、用藥處方與穿皮貼片輪替追蹤、突發表徵紀錄，以及動作障礙自我評估量表。結合 AI 摘要技術，可產出標準 A4 醫療級圖表報告，協助醫病雙方建立客觀且具延續性的問診方針。")
                .font(.system(size: 13.5))
                .foregroundColor(.secondary)
                .lineSpacing(5)
        }
        .modifier(CardModifier())
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("主要特色")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                featureRow(
                    title: "智慧手套與即時震顫特徵分析",
                    desc: "低功耗藍牙連線、馬達抑震監控、機械長度微調（-5cm 至 +5cm），即時運算 RMS 強度與 PSD 頻譜波峰，支援發作事件情境標籤歸檔。"
                )

                Divider()

                featureRow(
                    title: "彈性處方排程與穿皮貼片防呆輪替",
                    desc: "支援多時段常規口服處方設定與打卡推播；專為穿皮貼片提供 14 天黏貼部位防呆警示、患部膚況拍照記錄與 30 秒按壓倒數引導。"
                )

                Divider()

                featureRow(
                    title: "日常表徵影音牆與生理徵象監控",
                    desc: "文字與相片記錄肢體突發表徵（支援最多 5 張相片與貼文牆瀏覽檢視），同時追蹤血壓、血糖、體溫、體重、睡眠時數與飲食份量。"
                )

                Divider()

                featureRow(
                    title: "臨床動作障礙多維度自我評估量表",
                    desc: "參考臺灣動作障礙學會指引，提供 1 分鐘快篩、主題分類篩檢及完整 25 題每週評估表，涵蓋情緒、生活自理與動作功能，提交後自動銷除提醒。"
                )

                Divider()

                featureRow(
                    title: "家庭雙向照護連動與心情便利貼",
                    desc: "配對碼安全連動與照護者權限控管；家庭心情留言板支援 100 字限制、病患心情與留言擇一選填，以及「僅照護者查看」私密備忘功能。"
                )

                Divider()

                featureRow(
                    title: "AI 門診摘要與 A4 醫療級 PDF 報告",
                    desc: "AI 聊天室支援關鍵字與日曆檢索；回診前兩步驟快速生成溝通摘要，一鍵匯出包含 RMS 連續折線圖（0.20 警戒線）與每小時 PSD 頻譜圖之標準報告。"
                )
            }
        }
        .modifier(CardModifier())
    }

    private func featureRow(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text(desc)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 資料來源與免責聲明

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("資料來源與免責聲明")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                disclaimerSection(
                    title: "用藥清單與衛教資訊來源",
                    content: "本系統內建之用藥清單、藥品資料庫及相關衛教內容，主要源自「巴金森寶典」應用程式。該資料庫由臺大醫院巴金森症暨動作障礙中心，以及台灣巴金森之友協會共同合作開發，並經由神經內科主治醫師、專業藥師等醫療團隊進行嚴格審定與維護，以確保提供正確且具公信力之醫藥指引。"
                )

                Divider()

                disclaimerSection(
                    title: "症狀評估量表架構",
                    content: "本系統使用之日常症狀評估量表，其原始架構與評分標準參考自「台灣動作障礙學會」所發布之學術衛教資料，並融合「國際巴金森與動作障礙學會（MDS）」之臨床評估指標。資料經結構化與數位化整理，旨在協助使用者與照護者進行居家日常狀態之客觀紀錄與趨勢比對。"
                )

                Divider()

                disclaimerSection(
                    title: "醫療免責聲明",
                    content: "本系統所提供之震顫特徵運算數據、生理徵象紀錄、量表評估結果與 AI 生成之衛教摘要，純屬日常健康管理與門診醫病溝通之輔助參考，不具備任何醫療診斷、處方推薦或法定醫療器材效力，亦無法取代專業醫師之臨床診斷。若使用者有實際醫療、診斷或處方用藥調整需求，請務必尋求合格醫療院所及專科醫師之專業協助。"
                )
            }
        }
        .modifier(CardModifier())
    }

    private func disclaimerSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text(content)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("SteadyHope")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            Text("All Rights Reserved © 2026")
                .font(.system(size: 10))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// 通用資訊卡片視圖修飾器，統一設定內距、白色背景、圓角與微光陰影
struct CardModifier: ViewModifier {
    /// 定義修飾器對應內容之套用樣式
    /// - Parameter content: 原始視圖內容
    /// - Returns: 套用卡片外觀修飾後之視圖
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
    }
}
