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

    /// 畫面分頁、篩選日期與彈窗控制狀態
    @FocusState private var isInputFocused: Bool
    @State private var filterDate = Date()
    @State private var selectedTab: Int = 0
    @State private var showPatchPicker: Bool = false
    @State private var showPlanManageSheet: Bool = false
    @State private var isAddRecordExpanded: Bool = false
    @State private var showDeletePatchConfirm: Bool = false
    @State private var isPatchScheduleExpanded: Bool = true
    @State private var isAddSymptomExpanded: Bool = false

    /// 症狀影音多媒體選擇與預覽狀態
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var tempSelectedImages: [UIImage] = []
    @State private var currentPageIndex: Int = 0
    @State private var previewImage: UIImage?
    @State private var selectedSymptomItem: SymptomRecord?

    /// 編輯症狀紀錄多媒體狀態
    @State private var editSelectedMediaItems: [PhotosPickerItem] = []
    @State private var editPageIndex: Int = 0

    /// 列表互動滑動控制狀態
    @State private var activeSwipeRowID: Int? = nil

    /// 全螢幕圖片預覽項目雙向綁定計算屬性
    private var previewImageBinding: Binding<ImagePreviewItem?> {
        Binding(
            get: { previewImage.map { ImagePreviewItem(image: $0) } },
            set: { previewImage = $0?.image }
        )
    }

    /// 判斷目前篩選之日期是否為今日
    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(filterDate)
    }

    /// 判斷當前使用者角色是否為病患本人
    private var isPatient: Bool {
        loginVM.userData?.role == 0
    }

    /// 判斷當前使用者是否具備建立與管理用藥計畫之權限
    private var canManageMedPlan: Bool {
        if isPatient { return true }
        return loginVM.boundPartner?.canManageMedPlan ?? false
    }

    /// 判斷當前使用者是否具備新增與編輯用藥紀錄之權限
    private var canAddMedRecord: Bool {
        if isPatient { return true }
        return loginVM.boundPartner?.canAddMedRecord ?? false
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.98)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                medicationHeaderBar
                mainContentView
            }
        }
        .sheet(isPresented: $showPatchPicker) {
            PatchWorkflowSheet(
                medVM: medVM,
                planUserID: loginVM.userData?.userID ?? 0,
                editingRecord: medVM.editingRecord
            )
        }
        .sheet(isPresented: $showPlanManageSheet) {
            MedicationPlanManageView(
                planVM: planVM,
                currentUserID: loginVM.userData?.userID ?? 0
            )
        }
        .sheet(isPresented: $vitalsVM.showAddVitalsSheet) {
            HealthVitalsFormSheet(
                vitalsVM: vitalsVM,
                title: "新增生理數據",
                isEditing: false,
                filterDate: filterDate
            )
        }
        .sheet(item: $vitalsVM.editingVitals) { _ in
            HealthVitalsFormSheet(
                vitalsVM: vitalsVM,
                title: "編輯生理數據",
                isEditing: true,
                filterDate: filterDate
            )
        }
        .fullScreenCover(item: previewImageBinding) { item in
            ImagePreview(image: item.image) {
                previewImage = nil
            }
            .background(BackgroundClearView())
        }
        .onAppear {
            dataVM.bindPipeline(bleVM.pipeline)
        }
        .task {
            let today = Date().toString(format: "yyyy-MM-dd")
            await medVM.loadRecords(for: today)
            await planVM.loadAllPlans()
            await symptomVM.loadSymptoms(for: today)
            await vitalsVM.loadVitals(for: today)
        }
    }

    /// 頂部主標題與歷史日期快速篩選工具列
    private var medicationHeaderBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Text(!isPatient ? "\(loginVM.partnerName) 的健康與用藥" : "健康與用藥管理")
                    .font(.system(size: 26, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 7)

            Spacer()

            HStack(spacing: 6) {
                DatePicker(
                    "",
                    selection: $filterDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .transformEffect(.init(scaleX: 0.9, y: 0.9))

                if !isViewingToday {
                    Button(action: {
                        withAnimation {
                            filterDate = Date()
                        }
                    }) {
                        Text("回到今天")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.clear)
    }

    /// 主畫面分頁結構檢視
    private var mainContentView: some View {
        VStack(spacing: 0) {
            Picker("功能分頁", selection: $selectedTab) {
                Text("用藥清單").tag(0)
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

    /// 每日固定用藥打卡排程滾動檢視
    private var timelineScheduleView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("每日固定清單打卡")
                            .font(.headline)

                        Spacer()

                        if isPatient || canManageMedPlan {
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
            .padding(.bottom, 90)
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    /// 單次自訂用藥紀錄填報與當日服藥列表滾動檢視
    private var actualRecordsTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isPatient || canAddMedRecord {
                    addRecordCard
                }
                todayRecordsSectionCard
            }
            .padding()
            .padding(.bottom, 90)
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    /// 單次口服或注射用藥快速新增與編輯卡片
    private var addRecordCard: some View {
        let isEditing = medVM.editingRecordID != nil

        return VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAddRecordExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isEditing ? "編輯單次用藥紀錄" : "新增單次用藥紀錄")
                        .font(.headline)
                        .foregroundColor(isEditing ? .orange : .primary)
                    Spacer()

                    if isEditing {
                        Button(action: {
                            medVM.cancelEditing()
                            isAddRecordExpanded = false
                        }) {
                            Text("取消")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: isAddRecordExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.subheadline.bold())
                }
            }
            .buttonStyle(.plain)

            if isAddRecordExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "pill.fill")
                            .foregroundColor(.blue)
                            .frame(width: 20)

                        TextField("藥品名稱", text: $medVM.inputName)
                            .focused($isInputFocused)

                        Menu {
                            let nonPatchList = MedicationPresets.allList.filter { $0.medType != .patch }
                            let groupedList = Dictionary(
                                grouping: nonPatchList,
                                by: { $0.category }
                            )

                            ForEach(groupedList.keys.sorted(), id: \.self) { category in
                                Section(header: Text(category)) {
                                    ForEach(groupedList[category] ?? []) { item in
                                        Button {
                                            medVM.inputName = "\(item.name) (\(item.strength))"
                                            medVM.selectedMedType = item.medType

                                            let doseStr = item.commonDoses.first ?? (item.medType == .injection ? "1ml" : "1顆")
                                            if doseStr == "半顆" {
                                                medVM.inputDose = "0.5"
                                                medVM.inputUnit = "顆"
                                            } else {
                                                medVM.inputDose = String(
                                                    doseStr.filter { $0.isNumber || $0 == "." }
                                                )
                                                let unit = String(
                                                    doseStr.filter { !$0.isNumber && $0 != "." }
                                                )
                                                medVM.inputUnit = unit.isEmpty ? (item.medType == .injection ? "ml" : "顆") : unit
                                            }
                                        } label: {
                                            HStack {
                                                Text("\(item.name) (\(item.strength))")
                                                if item.medType == .injection {
                                                    Text("[針劑]")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("快選")
                                    .font(.subheadline.bold())
                                Image(systemName: "chevron.down")
                                    .font(.caption.bold())
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
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
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)
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
                       let token = AuthManager.shared.getToken() {
                        if medVM.editingRecordID != nil {
                            let dateString = filterDate.toString(format: "yyyy-MM-dd")
                            medVM.saveEditedRecord(targetDateString: dateString)
                        } else {
                            medVM.addRecord(currentUserID: uid, token: token)
                        }
                        isAddRecordExpanded = false
                    }
                } label: {
                    HStack {
                        Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                        Text(isEditing ? "修改紀錄" : "新增單次紀錄")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        medVM.isAddRecordValid
                            ? (isEditing ? Color.orange : Color.blue)
                            : Color.gray.opacity(0.4)
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

    /// 依據藥品給藥途徑產生專屬顏色與標籤
    /// - Parameter type: 藥品給藥型態列舉
    /// - Returns: 標籤視圖元件
    @ViewBuilder
    private func medTypeBadge(for type: MedicationType) -> some View {
        let title: String = {
            switch type {
            case .oral: return "口服"
            case .injection: return "針劑"
            case .patch: return "貼片"
            }
        }()

        let color: Color = {
            switch type {
            case .oral: return .blue
            case .injection: return .teal
            case .patch: return .orange
            }
        }()

        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    /// 固定常規用藥（口服與針劑）之打卡清單卡片
    private var oralScheduleCard: some View {
        let doseItems = planVM.oralDoseItems(for: filterDate)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pills.fill")
                    .foregroundColor(.blue)
                Text("固定用藥清單")
                    .font(.subheadline.bold())
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
                Text("目前尚無設定固定常規處方")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(doseItems.enumerated()), id: \.element.id) { index, item in
                        let isTaken = medVM.isDoseTaken(
                            for: item,
                            on: filterDate
                        )
                        HStack(spacing: 12) {
                            Button {
                                medVM.toggleDoseTaken(for: item, on: filterDate)
                            } label: {
                                Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(isTaken ? .green : .gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.plan.name)
                                        .font(.body.bold())
                                        .strikethrough(isTaken, color: .gray)
                                        .foregroundColor(isTaken ? .gray : .primary)
                                    if !item.plan.dose.isEmpty {
                                        Text("(\(item.plan.dose))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    if item.plan.creatorRole == 1 {
                                        Text("照護者代填")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundColor(.purple)
                                            .cornerRadius(4)
                                    }
                                }

                                medTypeBadge(for: item.plan.medType)
                            }
                            Spacer()
                            Text("\(item.timeString)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 6)
                        if index < doseItems.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    /// 每日貼片用藥狀態、黏貼部位與膚況檢核卡片
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
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundColor(.orange)
                    Text("每日貼片用藥")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(hasPlan ? "(已設定提醒)" : "(未設定提醒)")
                        .font(.caption2)
                        .foregroundColor(hasPlan ? .blue : .gray)
                    Spacer()
                    if isCompleted {
                        Text("已完成")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    } else {
                        Text("未完成")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: isPatchScheduleExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.subheadline.bold())
                        .padding(.leading, 4)
                }
            }
            .buttonStyle(.plain)

            if isPatchScheduleExpanded {
                Divider()

                if let record = todayRecord {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            HStack(spacing: 6) {
                                Text(record.name.isEmpty ? "貼片" : record.name)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)

                                if !record.dose.isEmpty {
                                    Text("(\(record.dose))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                if record.creatorRole == 1 {
                                    Text("照護者代填")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }

                            Spacer()

                            VStack(alignment: .center, spacing: 2) {
                                Text("\(record.date.toString(format: "HH:mm"))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.gray)

                                Text("已打卡")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            }
                        }

                        HStack(spacing: 8) {
                            if let region = record.patchRegion {
                                HStack(spacing: 4) {
                                    Image(systemName: "figure.stand")
                                    Text(region.rawValue)
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }

                            if let skin = record.skinCondition, !skin.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap")
                                    Text("皮膚：\(skin)")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(6)
                            }

                            Spacer()

                            if isPatient || canAddMedRecord {
                                Button {
                                    showDeletePatchConfirm = true
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 26)
                                        .background(Color.red.opacity(0.85))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .alert("確定要刪除貼片紀錄？", isPresented: $showDeletePatchConfirm) {
                                    Button("取消", role: .cancel) { }
                                    Button("刪除", role: .destructive) {
                                        if let index = medVM.medicationList.firstIndex(where: { r in
                                            r.medType == .patch && Calendar.current.isDate(r.date, inSameDayAs: filterDate)
                                        }) {
                                            medVM.deleteRecord(
                                                records: medVM.medicationList,
                                                at: IndexSet(integer: index)
                                            )
                                        }
                                    }
                                } message: {
                                    Text("刪除後將清除今日的貼片打卡、黏貼部位與膚況紀錄。")
                                }
                            }
                        }

                        if !record.skinImageDataList.isEmpty {
                            TabView {
                                ForEach(
                                    Array(record.skinImageDataList.enumerated()),
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
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .automatic))
                            .frame(height: 160)
                            .padding(.top, 4)
                        }

                        Button {
                            medVM.editingRecord = record
                            showPatchPicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "figure.walk")
                                    .font(.headline)
                                Text((isPatient || canAddMedRecord) ? "編輯貼片紀錄與部位流程" : "無編輯貼片紀錄權限")
                                    .font(.subheadline.bold())
                                Spacer()
                                if isPatient || canAddMedRecord {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                (isPatient || canAddMedRecord)
                                    ? Color.blue.opacity(0.08)
                                    : Color.gray.opacity(0.1)
                            )
                            .foregroundColor(
                                (isPatient || canAddMedRecord)
                                    ? .blue
                                    : .gray
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!(isPatient || canAddMedRecord))
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        medVM.editingRecord = nil
                        showPatchPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.walk")
                                .font(.headline)
                            Text((isPatient || canAddMedRecord) ? "開啟貼片紀錄與部位流程" : "無新增貼片紀錄權限")
                                .font(.subheadline.bold())
                            Spacer()
                            if isPatient || canAddMedRecord {
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            (isPatient || canAddMedRecord)
                                ? Color.blue.opacity(0.08)
                                : Color.gray.opacity(0.1)
                        )
                        .foregroundColor(
                            (isPatient || canAddMedRecord)
                                ? .blue
                                : .gray
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!(isPatient || canAddMedRecord))
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    /// 今日實際已服藥或已打卡之項目紀錄清單卡片
    private var todayRecordsSectionCard: some View {
        let filterDateStr = filterDate.toString(format: "yyyy-MM-dd")
        let filteredRecords = medVM.medicationList.filter { record in
            record.date.toString(format: "yyyy-MM-dd") == filterDateStr
        }
        let canMutateRecord = isPatient || canAddMedRecord

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.clipboard.fill")
                    .foregroundColor(.blue)
                Text("今日實際服藥紀錄 (\(filteredRecords.count) 筆)")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if filteredRecords.isEmpty {
                Text("目前尚無服藥打卡或單次紀錄")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, record in
                        SwipeableRecordRow(
                            id: record.id ?? index,
                            openRowID: $activeSwipeRowID,
                            isSwipeEnabled: canMutateRecord
                        ) {
                            if let idx = filteredRecords.firstIndex(where: { $0.id == record.id }) {
                                withAnimation {
                                    medVM.deleteRecord(
                                        records: filteredRecords,
                                        at: IndexSet(integer: idx)
                                    )
                                }
                            }
                        } onEdit: {
                            if record.medType == .patch {
                                medVM.editingRecord = record
                                showPatchPicker = true
                            } else {
                                medVM.startEditingRecord(record)
                                withAnimation {
                                    isAddRecordExpanded = true
                                }
                            }
                        } content: {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 6) {
                                        Text(record.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.primary)

                                        if !record.dose.isEmpty {
                                            Text("(\(record.dose))")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }

                                        if record.creatorRole == 1 {
                                            Text("照護者代填")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Color.purple.opacity(0.15)
                                                )
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                    }

                                    medTypeBadge(for: record.medType)
                                }

                                Spacer()

                                Text("\(record.date.toString(format: "HH:mm"))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                        }

                        if index < filteredRecords.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }

    /// 症狀與日常動作障礙影音紀錄牆分頁檢視
    private var mediaGalleryTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(.bottom, 90)
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

    /// 單一症狀多媒體或純文字筆記展示卡片
    /// - Parameter item: 症狀紀錄資料模型
    /// - Returns: 卡片視圖元件
    @ViewBuilder
    private func symptomCardView(for item: SymptomRecord) -> some View {
        let isProcessing =
            (item.id ?? 0) < 0 || symptomVM.processingIDs.contains(item.id ?? 0)
        let hasMedia = item.mediaData != nil || !item.mediaDataList.isEmpty

        Group {
            if hasMedia {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topTrailing) {
                        if let firstData = item.mediaData ?? item.mediaDataList.first,
                           let uiImage = UIImage(data: firstData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 120)
                                .cornerRadius(8)
                        }

                        if item.mediaDataList.count > 1 {
                            HStack(spacing: 3) {
                                Image(systemName: "square.fill.on.square.fill")
                                    .font(.caption2)
                                Text("\(item.mediaDataList.count)")
                                    .font(.caption2.bold())
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
                            Text(item.symptomNote.isEmpty ? "（無文字描述）" : item.symptomNote)
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            Text(item.date.toString(format: "M/d HH:mm"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        cardMenuOrProgress(for: item, isProcessing: isProcessing)
                    }
                }
                .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble.fill")
                                .font(.caption2)
                            Text("文字紀錄")
                                .font(.caption2.bold())
                        }
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.1))
                        .cornerRadius(5)

                        Spacer()

                        cardMenuOrProgress(for: item, isProcessing: isProcessing)
                    }

                    Text(item.symptomNote.isEmpty ? "（無文字描述）" : item.symptomNote)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.vertical, 2)

                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(item.date.toString(format: "M/d HH:mm"))
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(minHeight: 140)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        .opacity(isProcessing ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isProcessing {
                selectedSymptomItem = item
            }
        }
    }

    /// 症狀卡片右上角操作選單按鈕或非同步處理指示器
    /// - Parameters:
    ///   - item: 症狀紀錄資料模型
    ///   - isProcessing: 該項目是否正在與伺服器進行同步或處理
    /// - Returns: 按鈕或載入指示視圖
    @ViewBuilder
    private func cardMenuOrProgress(for item: SymptomRecord, isProcessing: Bool) -> some View {
        if isProcessing {
            ProgressView()
                .scaleEffect(0.8)
                .padding(2)
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
                    .contentShape(Rectangle())
            }
        }
    }

    /// 新增症狀與動作障礙影音或文字紀錄表單卡片
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

    /// 編輯特定症狀紀錄描述文字與多媒體之彈出工作頁面
    /// - Parameter item: 正在進行編輯之症狀紀錄模型
    /// - Returns: 工作表視圖元件
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

    /// 結合用藥時序與即時手部震顫走勢之藥效波動分析分頁檢視
    private var analyticsTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                AnalyticsTabView(
                    medVM: medVM,
                    dataVM: dataVM,
                    selectedDate: filterDate
                )
            }
            .padding()
            .padding(.bottom, 90)
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}

/// 提供向左滑動展開自訂操作按鈕（編輯、刪除）之通用互動列表列元件
struct SwipeableRecordRow<Content: View>: View {

    /// 項目唯一識別碼
    let id: Int

    /// 目前處於展開狀態之項目 ID 雙向綁定
    @Binding var openRowID: Int?

    /// 是否啟用左滑手勢互動
    var isSwipeEnabled: Bool = true

    /// 點擊刪除按鈕之回呼函式
    let onDelete: () -> Void

    /// 點擊編輯按鈕之回呼函式
    let onEdit: () -> Void

    /// 列表列主內容建構閉包
    let content: () -> Content

    /// 拖曳位移量狀態
    @State private var dragOffset: CGFloat = 0

    /// 後方操作按鈕區域寬度常數
    private let actionButtonsWidth: CGFloat = 136

    /// 判斷當前列表列是否正處於完全展開狀態
    private var isOpen: Bool {
        isSwipeEnabled && openRowID == id
    }

    /// 動態計算主內容層之水平平移量
    private var currentOffset: CGFloat {
        guard isSwipeEnabled else { return 0 }
        let base: CGFloat = isOpen ? -actionButtonsWidth : 0
        return base + dragOffset
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwipeEnabled {
                HStack(spacing: 12) {
                    Button {
                        close()
                        onEdit()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 34)
                                .background(Color.blue)
                                .clipShape(Capsule())

                            Text("編輯")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        close()
                        onDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 34)
                                .background(Color.red.opacity(0.88))
                                .clipShape(Capsule())

                            Text("刪除")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 10)
            }

            content()
                .background(Color.white)
                .offset(x: isSwipeEnabled ? currentOffset : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isOpen {
                        close()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard isSwipeEnabled else { return }
                            if abs(value.translation.width) > abs(value.translation.height) {
                                let base = isOpen ? -actionButtonsWidth : 0
                                let translation = value.translation.width
                                let target = base + translation
                                if target <= 0 {
                                    dragOffset = max(target, -actionButtonsWidth - 15) - base
                                }
                            }
                        }
                        .onEnded { value in
                            guard isSwipeEnabled else { return }
                            let totalMoved = (isOpen ? -actionButtonsWidth : 0) + value.translation.width
                            let velocity = value.predictedEndTranslation.width

                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                if totalMoved < -actionButtonsWidth / 2 || velocity < -150 {
                                    openRowID = id
                                } else {
                                    openRowID = nil
                                }
                                dragOffset = 0
                            }
                        }
                )
        }
        .clipped()
        .onChange(of: openRowID) {
            if openRowID != id && dragOffset != 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
        }
        .onChange(of: isSwipeEnabled) {
            if !isSwipeEnabled {
                dragOffset = 0
                if openRowID == id {
                    openRowID = nil
                }
            }
        }
    }

    /// 平滑收合展開之操作按鈕並重設位移量
    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            openRowID = nil
            dragOffset = 0
        }
    }
}
