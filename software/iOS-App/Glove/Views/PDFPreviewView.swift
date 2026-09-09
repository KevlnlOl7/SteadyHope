import PDFKit
import SwiftUI

/// PDF 報告預覽與匯出分享視圖
struct PDFPreviewView: View {
    /// 報告 PDF 二進位 Data
    let pdfData: Data

    /// 匯出檔案名稱
    let fileName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                // 渲染與展示生成的 PDF 內容
                PDFKitRepresentable(pdfData: pdfData)
                    .edgesIgnoringSafeArea(.bottom)
            }
            .navigationTitle("報告預覽")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: presentShareSheet) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("匯出")
                        }
                    }
                }
            }
        }
    }

    /// 呼叫 iOS 原生分享選單
    private func presentShareSheet() {
        // 將記憶體中的 PDF Data 寫入暫存目錄以取得實體檔案 URL
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileName).pdf")

        do {
            try pdfData.write(to: tempURL)

            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )

            // 尋找目前最上層的 ViewController 以彈出分享面板
            if let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController
            {

                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }

                // 針對 iPad 裝置進行 popoverPresentationController 相容性設定
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = topVC.view
                    popover.sourceRect = CGRect(
                        x: UIScreen.main.bounds.width / 2,
                        y: UIScreen.main.bounds.height / 2,
                        width: 0,
                        height: 0
                    )
                    popover.permittedArrowDirections = []
                }

                topVC.present(activityVC, animated: true, completion: nil)
            }

        } catch {
            print("無法產生暫存 PDF 檔案進行分享: \(error.localizedDescription)")
        }
    }
}
