import PhotosUI
import SwiftUI

struct PatchWorkflowSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var medVM: MedicationViewModel

    /// 使用者 ID
    var planUserID: Int

    /// 是否已撕除舊貼片之安全確認狀態
    @State private var hasRemovedOldPatch: Bool = false

    /// 當前選取之貼片部位
    @State private var selectedRegion: PatchRegion?

    /// 14 天內重複部位警告彈窗顯示狀態
    @State private var show14DayWarning: Bool = false

    /// 30 秒按壓倒數全螢幕檢視顯示狀態
    @State private var showCountdownModal: Bool = false

    /// 選取之皮膚狀況選項
    @State private var selectedSkinCondition: String = "正常"

    /// 暫存相片清單
    @State private var tempImages: [UIImage] = []

    /// 相簿選擇器項目清單
    @State private var selectedMediaItems: [PhotosPickerItem] = []

    /// 圖片預覽當前索引值
    @State private var currentPageIndex: Int = 0

    /// 全螢幕預覽圖片實例
    @State private var previewImage: UIImage?

    /// 是否啟用自訂皮膚狀況輸入
    @State private var isCustomCondition: Bool = false

    /// 自訂皮膚狀況描述文字
    @State private var customSkinCondition: String = ""

    /// 常見皮膚狀況預設選項清單
    let skinOptions = ["正常", "微紅", "發癢", "起疹子", "脫落"]

    /// 全螢幕圖片預覽綁定屬性
    private var previewImageBinding: Binding<ImagePreviewItem?> {
        Binding(
            get: { previewImage.map { ImagePreviewItem(image: $0) } },
            set: { previewImage = $0?.image }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    safetyCheckSection
                    bodyRegionPickerSection
                    skinConditionSection
                    startPatchButton
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .navigationTitle("貼片打卡與紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("部位輪替提醒", isPresented: $show14DayWarning) {
                Button("重新選擇部位", role: .cancel) {
                    selectedRegion = nil
                }
                Button("仍要使用此部位", role: .destructive) {
                    showCountdownModal = true
                }
            } message: {
                Text("貼片黏貼部位應輪流替換以減少對皮膚的刺激。系統偵測到您在 14 天內曾於此部位貼過，建議換到其他潔淨乾燥的皮膚表面。")
            }
            .fullScreenCover(isPresented: $showCountdownModal) {
                PatchCountdownView {
                    if let region = selectedRegion {
                        medVM.savePatchRecord(
                            region: region,
                            skinCondition: selectedSkinCondition,
                            isCustomCondition: isCustomCondition,
                            customCondition: customSkinCondition,
                            images: tempImages,
                            planUserID: planUserID
                        )
                    }
                    dismiss()
                }
                .background(BackgroundClearView())
            }
            .fullScreenCover(item: previewImageBinding) { item in
                ImagePreview(image: item.image) {
                    previewImage = nil
                }
                .background(BackgroundClearView())
            }
        }
    }

    /// 撕除舊貼片安全核對卡片
    private var safetyCheckSection: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.2)) {
                    hasRemovedOldPatch.toggle()
                }
            } label: {
                Image(
                    systemName: hasRemovedOldPatch
                        ? "checkmark.square.fill" : "square"
                )
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(hasRemovedOldPatch ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("我已確認撕除昨天的舊貼片")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(hasRemovedOldPatch ? .primary : .red)
                Text("防止舊貼片殘留導致重複用藥劑量過高")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            hasRemovedOldPatch
                ? Color.green.opacity(0.08) : Color.red.opacity(0.08)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(
                hasRemovedOldPatch
                    ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                lineWidth: 1.5
            )
        )
    }

    /// 解剖部位選擇區塊（含 14 天內重複使用標記）
    private var bodyRegionPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("選擇今日黏貼部位：")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(PatchRegion.allCases, id: \.self) { region in
                    let isRecentlyUsed = medVM.isRegionUsedInLast14Days(region)

                    Button {
                        selectedRegion = region
                    } label: {
                        HStack {
                            Image(
                                systemName: selectedRegion == region
                                    ? "largecircle.fill.circle" : "circle"
                            )
                            Text(region.rawValue)
                                .font(.subheadline.bold())

                            Spacer()

                            if isRecentlyUsed {
                                Text("14天內用過")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }
                        .padding()
                        .background(
                            selectedRegion == region
                                ? Color.blue.opacity(0.1)
                                : Color.gray.opacity(0.05)
                        )
                        .foregroundColor(
                            selectedRegion == region ? .blue : .primary
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(
                                selectedRegion == region
                                    ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
    }

    /// 皮膚狀況評估與局部照片上傳區塊
    private var skinConditionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("皮膚狀況追蹤：")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(skinOptions, id: \.self) { option in
                        Button {
                            isCustomCondition = false
                            selectedSkinCondition = option
                        } label: {
                            Text(option)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    (!isCustomCondition && selectedSkinCondition == option)
                                        ? Color.purple
                                        : Color.gray.opacity(0.12)
                                )
                                .foregroundColor(
                                    (!isCustomCondition && selectedSkinCondition == option)
                                        ? .white
                                        : .primary
                                )
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        isCustomCondition = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("其他")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isCustomCondition
                                ? Color.purple : Color.gray.opacity(0.12)
                        )
                        .foregroundColor(isCustomCondition ? .white : .primary)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isCustomCondition {
                TextField("請輸入皮膚狀況（例如：過敏、紅腫發熱）", text: $customSkinCondition)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }

            Divider().padding(.vertical, 4)

            Text("若有皮膚異常，可拍照記錄局部狀態（選填）")
                .font(.caption)
                .foregroundColor(.secondary)

            MediaManagementView(
                tempSelectedImages: $tempImages,
                selectedMediaItems: $selectedMediaItems,
                currentPageIndex: $currentPageIndex,
                previewImage: $previewImage
            )
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
    }

    /// 開始貼片與倒數流程確認按鈕
    private var startPatchButton: some View {
        let isReady = hasRemovedOldPatch && selectedRegion != nil

        return Button {
            if let region = selectedRegion,
               medVM.isRegionUsedInLast14Days(region)
            {
                show14DayWarning = true
            } else {
                showCountdownModal = true
            }
        } label: {
            HStack {
                Image(systemName: "hand.tap.fill")
                Text("確認部位並開始 30 秒按壓")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isReady ? Color.blue : Color.gray.opacity(0.4))
            .cornerRadius(12)
        }
        .disabled(!isReady)
    }
}
