import PhotosUI
import SwiftUI
import UIKit

/// 圖片全螢幕預覽包裝資料模型
struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 圖片全螢幕檢視與相簿儲存互動視圖
struct ImagePreview: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var showSaveSuccessToast = false
    @State private var saver = ImageSaver()

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack {
                HStack {
                    Spacer()

                    Button {
                        saveImageToAlbum()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)

                Spacer()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .shadow(
                        color: .black.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )
                    .onTapGesture {
                        onClose()
                    }

                Spacer()
            }

            if showSaveSuccessToast {
                VStack {
                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Text("已儲存至相簿")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.8))
                    )
                    .padding(.bottom, 60)
                }
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .opacity)
                )
            }
        }
    }

    /// 執行照片儲存至系統相簿流程並設定回呼處理
    private func saveImageToAlbum() {
        saver.onSuccess = {
            withAnimation {
                showSaveSuccessToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccessToast = false
                }
            }
        }

        saver.onError = { error in
            print("照片儲存至相簿失敗：\(error.localizedDescription)")
        }

        saver.writeToPhotoAlbum(image: image)
    }
}

/// 封裝 UIKit 寫入系統相簿回呼機制之輔助類別
final class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?

    /// 將指定 UIImage 寫入裝置本機相簿
    /// - Parameter image: 欲儲存之圖片
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(
            image,
            self,
            #selector(saveCompleted),
            nil
        )
    }

    /// 系統相簿儲存完成之目標回呼方法
    @objc private func saveCompleted(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        if let error {
            onError?(error)
        } else {
            onSuccess?()
        }
    }
}

enum ImageMediaHelper {
    /// 單張 UIImage 轉換為 JPEG 二進位 Data
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - compressionQuality: 壓縮品質（預設 0.8）
    /// - Returns: 壓縮後之二進位資料
    static func imageToData(
        _ image: UIImage,
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }

    /// 多張 UIImage 批量轉換為 JPEG 二進位 Data 陣列
    /// - Parameters:
    ///   - images: 原始圖片陣列
    ///   - compressionQuality: 壓縮品質（預設 0.8）
    /// - Returns: 二進位資料陣列
    static func imagesToData(
        _ images: [UIImage],
        compressionQuality: CGFloat = 0.8
    ) -> [Data] {
        images.compactMap {
            imageToData(
                $0,
                compressionQuality: compressionQuality
            )
        }
    }

    /// 單筆二進位 Data 轉換為 UIImage
    /// - Parameter data: 原始二進位資料
    /// - Returns: 解碼後之圖片
    static func dataToImage(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    /// 多筆二進位 Data 批量轉換為 UIImage 陣列
    /// - Parameter dataList: 二進位資料陣列
    /// - Returns: 解碼後之圖片陣列
    static func dataToImages(_ dataList: [Data]) -> [UIImage] {
        dataList.compactMap {
            UIImage(data: $0)
        }
    }
}

enum MediaPickerHelper {
    /// 從暫存圖片陣列中移除特定項目並自動校正當前分頁索引
    /// - Parameters:
    ///   - images: 暫存圖片陣列（雙向修改）
    ///   - index: 欲刪除項目之索引
    ///   - currentPageIndex: 當前選定分頁索引（雙向修改）
    static func removeImage(
        from images: inout [UIImage],
        at index: Int,
        currentPageIndex: inout Int
    ) {
        guard images.indices.contains(index) else {
            return
        }

        withAnimation {
            images.remove(at: index)

            if images.isEmpty {
                currentPageIndex = 0
            } else if currentPageIndex >= images.count {
                currentPageIndex = images.count - 1
            }
        }
    }
}

struct MediaManagementView: View {
    @Binding var tempSelectedImages: [UIImage]
    @Binding var selectedMediaItems: [PhotosPickerItem]
    @Binding var currentPageIndex: Int
    @Binding var previewImage: UIImage?

    /// 允許上傳之最大照片張數限制
    var maxImages: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("照片")
                    .font(.subheadline.bold())

                Spacer()

                Text("\(tempSelectedImages.count)/\(maxImages)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            PhotosPicker(
                selection: $selectedMediaItems,
                maxSelectionCount: maxImages - tempSelectedImages.count,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("新增照片")
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.08))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            .disabled(tempSelectedImages.count >= maxImages)

            if !tempSelectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(
                            Array(tempSelectedImages.enumerated()),
                            id: \.offset
                        ) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: 80,
                                        height: 80
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 8
                                        )
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        previewImage = image
                                    }

                                Button {
                                    MediaPickerHelper.removeImage(
                                        from: &tempSelectedImages,
                                        at: index,
                                        currentPageIndex: &currentPageIndex
                                    )
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.red)
                                        .background(
                                            Circle()
                                                .fill(.white)
                                        )
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 6)
                }
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            loadImages(from: newItems)
        }
    }

    /// 將 PhotosPicker 選取的項目非同步載入轉換為 UIImage 並更新至暫存陣列
    /// - Parameter items: 選取之 PhotosPickerItem 陣列
    private func loadImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            return
        }

        Task {
            var loadedImages: [UIImage] = []

            for item in items {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    continue
                }

                loadedImages.append(image)
            }

            await MainActor.run {
                let remainingCount = maxImages - tempSelectedImages.count
                let imagesToAdd = Array(loadedImages.prefix(max(0, remainingCount)))

                tempSelectedImages.append(contentsOf: imagesToAdd)

                if !tempSelectedImages.isEmpty {
                    currentPageIndex = tempSelectedImages.count - 1
                }

                selectedMediaItems.removeAll()
            }
        }
    }
}

/// 共用分頁滑動圖片輪播檢視元件
struct ImageCarouselView: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    var height: CGFloat = 320
    var onTap: ((UIImage) -> Void)?

    var body: some View {
        Group {
            if images.isEmpty {
                emptyView
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(
                        Array(images.enumerated()),
                        id: \.offset
                    ) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: height
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12
                                )
                            )
                            .tag(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onTap?(image)
                            }
                    }
                }
                .frame(height: height)
                .tabViewStyle(
                    PageTabViewStyle(
                        indexDisplayMode: .automatic
                    )
                )
                .onChange(of: images.count) { _, newCount in
                    if newCount == 0 {
                        currentIndex = 0
                    } else if currentIndex >= newCount {
                        currentIndex = newCount - 1
                    }
                }
            }
        }
    }

    /// 無圖片時呈現之留白預設圖示視圖
    private var emptyView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .frame(height: height)
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
    }
}

/// 透過將 UIKit 父層視圖背景設為透明以支援全螢幕覆蓋模態之輔助視圖
struct BackgroundClearView: UIViewRepresentable {
    /// 建立底層 UIView 實體並異步調整上層容器背景為透明
    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }

        return view
    }

    /// 更新 UIKit 視圖
    func updateUIView(_ uiView: UIView, context: Context) {}
}
