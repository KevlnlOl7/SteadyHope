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

    /// 是否包含圖片
    private var hasImages: Bool {
        !images.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasImages {
                        ImageCarouselView(
                            images: images,
                            currentIndex: $currentIndex,
                            height: 320
                        ) { image in
                            previewImage = ImagePreviewItem(image: image)
                        }

                        // 下方文字與時間
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(dateString)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            Text(note.isEmpty ? "（無文字描述）" : note)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 5) {
                                    Image(systemName: "text.bubble.fill")
                                        .font(.caption2)
                                    Text("文字紀錄")
                                        .font(.caption2.bold())
                                }
                                .foregroundColor(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.1))
                                .cornerRadius(6)

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text(dateString)
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text("症狀描述")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                Text(note.isEmpty ? "（無文字描述）" : note)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
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
