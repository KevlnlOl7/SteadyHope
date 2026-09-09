import Foundation
import SwiftUI

struct AboutUsView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                
                headerSection
                introCard
                featuresCard
                disclaimerCard

                Spacer(minLength: 10)

            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("關於我們")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image("SteadyHopeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            VStack(spacing: 6) {
                Text("SteadyHope")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系統簡介")
                .font(.headline)
                .foregroundColor(.primary)

            Text("本系統專為照護者與使用者打造，整合用藥排程、生理量測數據、日常症狀評估與智慧提醒，提供即時、精準的遠距健康追蹤。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(5)
        }
        .modifier(CardModifier())
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("主要特色")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("• 智慧用藥與回診提醒")
                Text("• 生理訊號與動作症狀追蹤")
                Text("• MDS-UPDRS 臨床症狀自我評估")
                Text("• 照護者即時狀態連動")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .modifier(CardModifier())
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("資料來源與免責聲明")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 20) {
                disclaimerSection(
                    title: "用藥清單與衛教資訊",
                    content: "本系統內建之用藥清單、藥品資料庫及相關衛教內容，主要源自「巴金森寶典」應用程式。該資料庫由臺大醫院巴金森症暨動作障礙中心，以及台灣巴金森之友協會共同合作開發，並經由神經內科主治醫師、專業藥師等醫療團隊進行嚴格審定與維護，以確保提供正確且具公信力之資訊。"
                )

                disclaimerSection(
                    title: "症狀評估量表",
                    content: "本系統使用之日常症狀評估量表，其原始架構與評分標準參考自「台灣動作障礙學會」所發布之學術衛教資料，並融合「國際巴金森與動作障礙學會 (MDS)」之臨床評估指標。資料已由系統進行結構化與數位化整理，旨在協助使用者與照護者進行日常狀態之紀錄與追蹤。"
                )

                disclaimerSection(
                    title: "醫療免責聲明",
                    content: "系統提供之評估結果與衛教資訊僅供學術研究與居家照護參考，不具備任何醫療診斷效力，亦無法取代專業醫師之臨床評估。若使用者有實際醫療、診斷或用藥調整需求，請務必尋求正規醫療院所及專業醫事人員之協助。"
                )
            }
        }
        .modifier(CardModifier())
    }

    /// 單一免責聲明或資料來源小段落視圖
    /// - Parameters:
    ///   - title: 段落小標題
    ///   - content: 詳細說明內文
    /// - Returns: 排版完成之垂直堆疊視圖
    private func disclaimerSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(5)
        }
    }
}

/// 通用資訊卡片視圖修飾器，統一設定內距、白色背景、圓角與微光陰影
struct CardModifier: ViewModifier {
    /// 定義修飾器對應內容之套用樣式
    /// - Parameter content: 原始視圖內容
    /// - Returns: 套用卡片外觀修飾後之視圖
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
