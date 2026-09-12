import SwiftUI

struct WhatsNewSheetView: View {
    let version: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("歡迎使用 SteadyHope")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("版本 \(version) 全新功能上線")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.top, 28)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    WhatsNewFeatureRow(
                        icon: "hand.wave.fill",
                        iconColor: Color(hex: "3182ce"),
                        title: "智慧手套與震顫監控",
                        description: "藍牙自動連線與手套電量顯示，即時掌握手部震顫變化。"
                    )

                    WhatsNewFeatureRow(
                        icon: "pills.fill",
                        iconColor: Color(hex: "dd6b20"),
                        title: "用藥排程與貼片管理",
                        description: "輕鬆記錄每日用藥時間、貼片用藥部位與皮膚狀況等資訊。"
                    )

                    WhatsNewFeatureRow(
                        icon: "bell.badge.fill",
                        iconColor: Color(hex: "e53e3e"),
                        title: "貼心生活提醒",
                        description: "定時推播吃藥、回診與領藥時間，讓日常照顧井然有序。"
                    )

                    WhatsNewFeatureRow(
                        icon: "square.grid.2x2.fill",
                        iconColor: Color(hex: "805ad5"),
                        title: "家人心情留言板",
                        description: "以日期輕鬆翻閱留言，隨時傳遞關心，照護者也能享有私密留言空間。"
                    )

                    WhatsNewFeatureRow(
                        icon: "heart.text.square.fill",
                        iconColor: Color(hex: "38a169"),
                        title: "表徵牆與生理健康",
                        description: "隨手記錄身體狀態與照片，同步追蹤血壓、血糖、體溫與體重等數據。"
                    )

                    WhatsNewFeatureRow(
                        icon: "checklist",
                        iconColor: Color(hex: "2b6cb0"),
                        title: "健康評估與量表",
                        description: "提供快速快篩與每週健康量表，幫助長期追蹤身體狀態。"
                    )

                    WhatsNewFeatureRow(
                        icon: "person.2.fill",
                        iconColor: Color(hex: "0bc5ea"),
                        title: "家屬安心互相連結",
                        description: "輸入專屬連動碼即可與家人綁定，隨時給予即時關心。"
                    )

                    WhatsNewFeatureRow(
                        icon: "doc.text.viewfinder",
                        iconColor: Color(hex: "319795"),
                        title: "AI 門診摘要與就醫報告",
                        description: "隨身 AI 助理，一鍵彙整紀錄，輕鬆產生看診前報告。"
                    )

                    WhatsNewFeatureRow(
                        icon: "book.fill",
                        iconColor: Color(hex: "d69e2e"),
                        title: "內建系統操作說明",
                        description: "隨時查閱圖文並茂的操作指引，輕鬆掌握各項功能。"
                    )
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 10)

            Button(action: onDismiss) {
                Text("開始使用")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

// 單一功能特色展示列
struct WhatsNewFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}
