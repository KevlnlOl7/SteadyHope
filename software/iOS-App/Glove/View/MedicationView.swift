import PhotosUI
import SwiftUI

struct MedicationView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel

    @StateObject private var medVM = MedicationViewModel()
    @StateObject private var planVM = MedicationPlanViewModel()
    @StateObject private var symptomVM = SymptomViewModel()
    @StateObject private var vitalsVM = HealthVitalsViewModel()
    @StateObject var bleVM: BluetoothViewModel

    @FocusState private var isInputFocused: Bool
    @State private var filterDate = Date()
    @State private var selectedTab: Int = 0
    @State private var showPatchPicker: Bool = false
    @State private var showPlanManageSheet: Bool = false

    /// 單次口服用藥輸入表單展開狀態
    @State private var isAddRecordExpanded: Bool = false

    /// 影音牆多媒體選擇與預覽狀態
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var tempSelectedImages: [UIImage] = []
    @State private var currentPageIndex: Int = 0
    @State private var previewImage: UIImage?
    @State private var selectedSymptomItem: SymptomRecord?

    /// 編輯症狀紀錄多媒體狀態
    @State private var editSelectedMediaItems: [PhotosPickerItem] = []
    @State private var editPageIndex: Int = 0

    /// 全螢幕圖片預覽綁定屬性
    private var previewImageBinding: Binding<ImagePreviewItem?> {
        Binding(
            get: { previewImage.map { ImagePreviewItem(image: $0) } },
            set: { previewImage = $0?.image }
        )
    }

    var body: some View {
        NavigationStack {
            mainContentView
                .navigationTitle("健康與用藥管理")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        DatePicker(
                            "",
                            selection: $filterDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .onChange(of: filterDate) { _, newValue in
                            Task {
                                let dateString = newValue.toString(
                                    format: "yyyy-MM-dd"
                                )
                                await medVM.loadRecords(for: dateString)
                                await symptomVM.loadSymptoms(for: dateString)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showPatchPicker) {
                    PatchWorkflowSheet(
                        medVM: medVM,
                        planUserID: loginVM.userData?.userID ?? 0
                    )
                }
                .sheet(isPresented: $showPlanManageSheet) {
                    MedicationPlanManageView(
                        planVM: planVM,
                        currentUserID: loginVM.userData?.userID ?? 0
                    )
                }
                .fullScreenCover(item: previewImageBinding) { item in
                    ImagePreview(image: item.image) {
                        previewImage = nil
                    }
                    .background(BackgroundClearView())
                }
                .onAppear {
                    dataVM.load5HzCSVAndSimulate()
                }
                .task {
                    let today = Date().toString(format: "yyyy-MM-dd")

                    await medVM.loadRecords(for: today)
                    await planVM.loadAllPlans()
                    await symptomVM.loadSymptoms(for: today)
                }
        }
    }

    /// 主畫面分頁結構檢視
    private var mainContentView: some View {
        VStack(spacing: 0) {
            Picker("功能分頁", selection: $selectedTab) {
                Text("每日行程").tag(0)
                Text("服藥紀錄").tag(1)
                Text("生理健康").tag(2)
                Text("表徵紀錄").tag(3)
                Text("藥效波動").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))

            selectedTabView
        }
    }

    /// 根據當前選取分頁呈現對應內容檢視
    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case 0:
            timelineScheduleView
        case 1:
            actualRecordsTabView
        case 2:
            HealthVitalsTabView(
                vitalsVM: vitalsVM,
                isCaregiver: loginVM.userData?.role == 1,
                filterDate: filterDate
            )
        case 3:
            mediaGalleryTabView
        case 4:
            analyticsTabView
        default:
            timelineScheduleView
        }
    }

    /// 照護對象使用者資訊標頭檢視
    @ViewBuilder
    private var patientHeaderView: some View {
        if loginVM.userData?.role == 1 {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("照護對象")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(loginVM.userData?.userName ?? "患者姓名")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.white)
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        }
    }

    /// 每日固定行程與打卡排程檢視
    private var timelineScheduleView: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientHeaderView
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("每日固定清單打卡")
                            .font(.headline)

                        Spacer()

                        if loginVM.userData?.role == 0 {
                            Button {
                                showPlanManageSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName:
                                            "list.bullet.rectangle.portrait"
                                    )
                                    Text("管理用藥清單")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    patchScheduleCard
                    oralScheduleCard
                }
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    /// 單次服藥與實際用藥紀錄檢視
    private var actualRecordsTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientHeaderView
                if loginVM.userData?.role == 0 {
                    addRecordCard
                }
                todayRecordsSectionCard
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    /// 新增單次口服用藥紀錄輸入卡片
    private var addRecordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAddRecordExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("新增單次口服用藥紀錄")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(
                        systemName: isAddRecordExpanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .foregroundColor(.gray)
                    .font(.subheadline.bold())
                }
            }
            .buttonStyle(.plain)

            if isAddRecordExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "pill.fill").foregroundColor(.blue)
                            .frame(width: 20)
                        TextField("藥品名稱", text: $medVM.inputName)
                            .focused($isInputFocused)
                    }
                    .padding()
                    Divider().padding(.leading, 44)

                    HStack(spacing: 12) {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        TextField("用量", text: $medVM.inputDose)
                            .keyboardType(.decimalPad)
                            .focused($isInputFocused)
                            .frame(width: 60)
                        TextField("單位", text: $medVM.inputUnit)
                            .focused($isInputFocused)
                            .frame(width: 60)
                        Spacer()
                    }
                    .padding()
                    Divider().padding(.leading, 44)

                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill").foregroundColor(.blue)
                            .frame(width: 20)
                        DatePicker("時間", selection: $medVM.inputDate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                .cornerRadius(10)

                Button {
                    isInputFocused = false
                    if let uid = loginVM.userData?.userID,
                        let token = AuthManager.shared.getToken()
                    {
                        medVM.addRecord(currentUserID: uid, token: token)
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("新增單次紀錄")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        medVM.isAddRecordValid
                            ? Color.blue : Color.gray.opacity(0.4)
                    )
                    .cornerRadius(10)
                }
                .disabled(!medVM.isAddRecordValid)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 口服用藥每日打卡清單卡片
    private var oralScheduleCard: some View {
        let doseItems = planVM.oralDoseItems(for: filterDate)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pill.fill").foregroundColor(.blue)
                Text("口服用藥清單").font(.subheadline.bold())
                Spacer()
                let completedCount = doseItems.filter { item in
                    medVM.isDoseTaken(for: item, on: filterDate)
                }.count
                Text("\(completedCount)/\(doseItems.count) 完成")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()

            if doseItems.isEmpty {
                Text("目前尚無設定固定口服處方")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(doseItems.enumerated()), id: \.element.id) {
                        index,
                        item in
                        let isTaken = medVM.isDoseTaken(
                            for: item,
                            on: filterDate
                        )
                        HStack(spacing: 12) {
                            Button {
                                medVM.toggleDoseTaken(for: item, on: filterDate)
                            } label: {
                                Image(
                                    systemName: isTaken
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .font(.title3)
                                .foregroundColor(
                                    isTaken ? .green : .gray.opacity(0.5)
                                )
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.plan.name)
                                        .font(.body.bold())
                                        .strikethrough(isTaken, color: .gray)
                                        .foregroundColor(
                                            isTaken ? .gray : .primary
                                        )
                                    if !item.plan.dose.isEmpty {
                                        Text("(\(item.plan.dose))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Text(item.plan.medType.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                            Spacer()
                            Text("\(item.timeString)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 6)
                        if index < doseItems.count - 1 { Divider() }
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    @State private var isPatchScheduleExpanded: Bool = true

    /// 貼片用藥每日打卡與部位檢視卡片
    private var patchScheduleCard: some View {
        let hasPlan = planVM.hasExistingPatch
        let todayRecord = medVM.medicationList.first { record in
            let typeMatch = record.medType == .patch
            let dateMatch = Calendar.current.isDate(
                record.date,
                inSameDayAs: filterDate
            )
            return typeMatch && dateMatch
        }
        let isCompleted = todayRecord != nil

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPatchScheduleExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2.fill").foregroundColor(
                        .orange
                    )
                    Text("每日貼片用藥")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(hasPlan ? "(已設定提醒)" : "(未設定提醒)")
                        .font(.caption2)
                        .foregroundColor(hasPlan ? .blue : .gray)
                    Spacer()
                    if isCompleted {
                        Text("已完成").font(.caption.bold()).foregroundColor(
                            .green
                        )
                    } else {
                        Text("未完成").font(.caption.bold()).foregroundColor(
                            .secondary
                        )
                    }
                    Image(
                        systemName: isPatchScheduleExpanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .foregroundColor(.gray)
                    .font(.subheadline.bold())
                    .padding(.leading, 4)
                }
            }
            .buttonStyle(.plain)

            if isPatchScheduleExpanded {
                Divider()

                if let record = todayRecord {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Button {
                                if let index = medVM.medicationList.firstIndex(
                                    where: { r in
                                        r.medType == .patch
                                            && Calendar.current.isDate(
                                                r.date,
                                                inSameDayAs: filterDate
                                            )
                                    })
                                {
                                    medVM.deleteRecord(
                                        records: medVM.medicationList,
                                        at: IndexSet(integer: index)
                                    )
                                }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.name.isEmpty ? "貼片" : record.name)
                                    .font(.body.bold())
                                    .foregroundColor(.gray)
                                    .strikethrough(true, color: .gray)
                                Text(
                                    "\(record.date.toString(format: "HH:mm"))"
                                )
                                .font(.caption)
                                .foregroundColor(.gray)
                            }
                            Spacer()
                            Button {
                                showPatchPicker = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "pencil")
                                    Text("編輯")
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.12))
                                .foregroundColor(.primary)
                                .cornerRadius(6)
                            }
                            Text("已打卡")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }

                        HStack(spacing: 8) {
                            if let region = record.patchRegion {
                                HStack(spacing: 4) {
                                    Image(systemName: "figure.stand")
                                    Text(region.rawValue)
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            if let skin = record.skinCondition, !skin.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap")
                                    Text("皮膚：\(skin)")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(6)
                            }
                            Spacer()
                        }
                        .padding(.leading, 32)

                        if !record.skinImageDataList.isEmpty {
                            TabView {
                                ForEach(
                                    Array(
                                        record.skinImageDataList.enumerated()
                                    ),
                                    id: \.offset
                                ) { _, data in
                                    if let uiImage = UIImage(data: data) {
                                        Button {
                                            previewImage = uiImage
                                        } label: {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(height: 160)
                                                .frame(maxWidth: .infinity)
                                                .clipShape(
                                                    RoundedRectangle(
                                                        cornerRadius: 8
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(
                                                        cornerRadius: 8
                                                    )
                                                    .stroke(
                                                        Color.gray.opacity(0.2),
                                                        lineWidth: 1
                                                    )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .automatic))
                            .frame(height: 160)
                            .padding(.leading, 32)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showPatchPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.walk").font(.headline)
                            Text("開啟貼片紀錄與部位流程").font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "chevron.right").font(
                                .caption.bold()
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.08))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    /// 今日實際服藥紀錄清單檢視卡片
    private var todayRecordsSectionCard: some View {
        let filteredRecords = medVM.medicationList.filter { record in
            Calendar.current.isDate(record.date, inSameDayAs: filterDate)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.clipboard.fill").foregroundColor(.blue)
                Text("今日實際服藥紀錄 (\(filteredRecords.count) 筆)").font(.headline)
            }
            Divider()

            if filteredRecords.isEmpty {
                Text("目前尚無服藥打卡或單次紀錄")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(filteredRecords) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.name).font(.body.bold())
                                    if !record.dose.isEmpty {
                                        Text("(\(record.dose))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Text(record.medType.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        record.medType == .patch
                                            ? Color.orange.opacity(0.15)
                                            : Color.blue.opacity(0.15)
                                    )
                                    .foregroundColor(
                                        record.medType == .patch
                                            ? .orange : .blue
                                    )
                                    .cornerRadius(4)
                            }
                            Spacer()
                            Text("時間：\(record.date.toString(format: "HH:mm"))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 0,
                                bottom: 6,
                                trailing: 0
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        medVM.deleteRecord(
                            records: filteredRecords,
                            at: offsets
                        )
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(filteredRecords.count * 52))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    /// 症狀與動作障礙影音紀錄牆分頁檢視
    private var mediaGalleryTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                patientHeaderView

                if loginVM.userData?.role == 0 {
                    addSymptomCard
                }

                Text("症狀與動作障礙影音紀錄牆")
                    .font(.headline)

                if symptomVM.isFetchingData {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("載入資料中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                } else if symptomVM.symptomList.isEmpty {
                    Text("目前尚無上傳之影音紀錄")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()), GridItem(.flexible()),
                        ],
                        spacing: 12
                    ) {
                        ForEach(symptomVM.symptomList) { item in
                            symptomCardView(for: item)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
        .sheet(item: $selectedSymptomItem) { item in
            MediaPostDetail(
                title: "症狀紀錄詳情",
                note: item.symptomNote,
                dateString: item.date.toString(format: "yyyy/MM/dd HH:mm"),
                mediaDataList: item.mediaDataList
            )
        }
        .sheet(item: $symptomVM.editingSymptomItem) { item in
            editSymptomSheet(for: item)
        }
    }

    /// 單一症狀影音展示卡片檢視
    @ViewBuilder
    private func symptomCardView(for item: SymptomRecord) -> some View {
        let isProcessing =
            (item.id ?? 0) < 0 || symptomVM.processingIDs.contains(item.id ?? 0)

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let firstData = item.mediaData,
                    let uiImage = UIImage(data: firstData)
                {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: "video.fill").foregroundColor(
                                .gray
                            )
                        )
                        .cornerRadius(8)
                }

                if item.mediaDataList.count > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.fill.on.square.fill").font(
                            .caption2
                        )
                        Text("\(item.mediaDataList.count)").font(
                            .caption2.bold()
                        )
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(6)
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        item.symptomNote.isEmpty ? "（無文字描述）" : item.symptomNote
                    )
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)

                    Text(item.date.toString(format: "M/d HH:mm"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(4)
                } else {
                    Menu {
                        Button {
                            symptomVM.startEditing(item)
                        } label: {
                            Label("編輯紀錄", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            symptomVM.deleteSymptom(item)
                        } label: {
                            Label("刪除紀錄", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                            .padding(4)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.03), radius: 2)
        .opacity(isProcessing ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isProcessing {
                selectedSymptomItem = item
            }
        }
    }

    @State private var isAddSymptomExpanded: Bool = false

    /// 新增症狀與動作障礙影音紀錄卡片
    private var addSymptomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAddSymptomExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("紀錄突發症狀 / 動作障礙")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(
                        systemName: isAddSymptomExpanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .foregroundColor(.gray)
                    .font(.subheadline.bold())
                }
            }
            .buttonStyle(.plain)

            if isAddSymptomExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "症狀描述（例如：手部顫抖、步態凍結）",
                        text: $symptomVM.symptomNote
                    )
                    .textFieldStyle(.roundedBorder)
                }

                MediaManagementView(
                    tempSelectedImages: $tempSelectedImages,
                    selectedMediaItems: $selectedMediaItems,
                    currentPageIndex: $currentPageIndex,
                    previewImage: $previewImage
                )

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tempSelectedImages.removeAll()
                            symptomVM.symptomNote = ""
                            currentPageIndex = 0
                            isAddSymptomExpanded = false
                        }
                    }) {
                        Text("取消")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Color.gray.opacity(
                                    symptomVM.isAddSymptomValid(
                                        tempImagesCount: tempSelectedImages
                                            .count
                                    ) ? 0.15 : 0.05
                                )
                            )
                            .foregroundColor(
                                symptomVM.isAddSymptomValid(
                                    tempImagesCount: tempSelectedImages.count
                                ) ? .secondary : .gray.opacity(0.4)
                            )
                            .cornerRadius(10)
                    }
                    .disabled(
                        !symptomVM.isAddSymptomValid(
                            tempImagesCount: tempSelectedImages.count
                        )
                    )

                    Button {
                        if let uid = loginVM.userData?.userID {
                            symptomVM.addSymptomRecord(
                                currentUserID: uid,
                                images: tempSelectedImages,
                                date: filterDate
                            )

                            withAnimation(.easeInOut(duration: 0.2)) {
                                tempSelectedImages.removeAll()
                                currentPageIndex = 0
                                symptomVM.symptomNote = ""
                                isAddSymptomExpanded = false
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("新增症狀紀錄")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            symptomVM.isAddSymptomValid(
                                tempImagesCount: tempSelectedImages.count
                            )
                                ? Color.red.opacity(0.85)
                                : Color.gray.opacity(0.4)
                        )
                        .cornerRadius(10)
                    }
                    .disabled(
                        !symptomVM.isAddSymptomValid(
                            tempImagesCount: tempSelectedImages.count
                        )
                    )
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4)
    }

    /// 編輯症狀紀錄彈出檢視表單
    @ViewBuilder
    private func editSymptomSheet(for item: SymptomRecord) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("修改症狀文字描述").font(.headline)
                    TextField(
                        "症狀描述（例如：手部顫抖、步態凍結）",
                        text: $symptomVM.editSymptomNote
                    )
                    .textFieldStyle(.roundedBorder)
                    Divider()
                    Text("調整影音照片").font(.headline)
                    MediaManagementView(
                        tempSelectedImages: $symptomVM.editTempImages,
                        selectedMediaItems: $editSelectedMediaItems,
                        currentPageIndex: $editPageIndex,
                        previewImage: $previewImage
                    )
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .navigationTitle("編輯症狀紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { symptomVM.editingSymptomItem = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        symptomVM.saveEditedSymptom(originalItem: item)
                    }
                    .bold()
                }
            }
        }
    }

    /// 藥效波動趨勢與感測數據分析分頁檢視
    private var analyticsTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientHeaderView
                AnalyticsTabView(
                    medVM: medVM,
                    dataVM: dataVM,
                    selectedDate: filterDate
                )
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}
