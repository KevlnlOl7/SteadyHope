import Foundation
import WebKit

/// 將 HTML 字串在幕後轉換為 A4 規格的 PDF Data
class PDFDataGenerator: NSObject, WKNavigationDelegate {

    // 單例模式：確保全局只有一個產生器實例，優化記憶體開銷
    static let shared = PDFDataGenerator()

    // 幕後用於渲染 HTML 內容的隱藏 WKWebView
    private var webView: WKWebView?

    // 非同步生成完成後的回傳閉包
    private var completion: ((Data?) -> Void)?

    // 限制外部初始化，強迫使用單例模式
    private override init() { super.init() }

    /// 生成 PDF 的主入口
    /// - Parameters:
    ///   - htmlContent: 欲轉換的 HTML 語法字串
    ///   - completion: 完成後的Callback，傳回 PDF Data
    func generatePDFData(from htmlContent: String, completion: @escaping (Data?) -> Void
    ) {
        self.completion = completion

        // WKWebView 屬於 UI 元件，必須在主執行緒 (Main Thread) 建立與操作
        DispatchQueue.main.async {
            self.webView = WKWebView()
            self.webView?.navigationDelegate = self
            self.webView?.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    /// 網頁內容完全載入並排版完成後觸發
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 初始化列印渲染器
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(
            webView.viewPrintFormatter(),
            startingAtPageAt: 0
        )

        // 設定 A4 紙張標準尺寸 Points 與邊距
        let pagePaperWidth: CGFloat = 595.2
        let pagePaperHeight: CGFloat = 841.8
        let margin: CGFloat = 56

        let paperRect = CGRect(
            x: 0,
            y: 0,
            width: pagePaperWidth,
            height: pagePaperHeight
        )
        let printableRect = CGRect(
            x: margin,
            y: margin,
            width: pagePaperWidth - (margin * 2),
            height: pagePaperHeight - (margin * 2)
        )

        // 使用 KVC 強制寫入列印渲染器的唯讀屬性
        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(
            NSValue(cgRect: printableRect),
            forKey: "printableRect"
        )

        // 建立繪圖上下文，並將內容分頁繪製至 NSMutableData (可變資料類別)
        let pdfData = NSMutableData()
        UIGraphicsBeginImageContextWithOptions(paperRect.size, false, 0.0)
        UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil)

        // 分頁
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: paperRect)
        }

        // 關閉並結束繪圖
        UIGraphicsEndPDFContext()
        UIGraphicsEndImageContext()

        // 回傳最終生成的 PDF Data
        self.completion?(pdfData as Data)

        // 記憶體優化：手動銷毀 webView 實例，釋放 WebKit 佔用的記憶體
        self.webView = nil
    }
}
