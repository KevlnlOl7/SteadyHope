import PDFKit
import SwiftUI

/// 將 iOS 原生 PDFView 包裝為 SwiftUI 可使用的 UIViewRepresentable 元件
struct PDFKitRepresentable: UIViewRepresentable {
    /// PDF 二進位資料
    let pdfData: Data

    /// 初始化並設定 PDF 瀏覽視圖
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.maxScaleFactor = 4.0
        pdfView.minScaleFactor = 0.5
        return pdfView
    }

    /// 當 pdfData 內容變更時，重新載入並更新 PDF 文件
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: pdfData)
    }
}
