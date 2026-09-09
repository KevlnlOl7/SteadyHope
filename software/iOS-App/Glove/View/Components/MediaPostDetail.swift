import SwiftUI

struct MediaPostDetail: View {
    /// 導覽列標題文字
    let title: String

    /// 紀錄文字描述或備註內容
    let note: String

    /// 紀錄日期時間顯示字串
    let dateString: String

    /// 多媒體二進位資料清單
    let mediaDataList: [Data]

    @Environment(\.dismiss) private var dismiss

    /// 當前輪播圖片索引值
    @State private var currentIndex = 0

    /// 全螢幕預覽圖片項目
    @State private var previewImage: ImagePreviewItem?

    /// 將二進位資料清單解析為 UIImage 圖片陣列
    private var images: [UIImage] {
        ImageMediaHelper.dataToImages(mediaDataList)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    ImageCarouselView(
                        images: images,
                        currentIndex: $currentIndex,
                        height: 320
                    ) { image in
                        previewImage = ImagePreviewItem(image: image)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        Text(dateString)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(note)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                    .padding(.horizontal, 4)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(item: $previewImage) { item in
                ImagePreview(
                    image: item.image,
                    onClose: {
                        previewImage = nil
                    }
                )
            }
        }
    }
}
