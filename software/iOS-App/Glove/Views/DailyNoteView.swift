import SwiftData
import SwiftUI

struct DailyNoteView: View {
    @StateObject private var viewModel: DailyNoteViewModel
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.modelContext) private var modelContext

    /// 日期選取與彈窗狀態
    @State private var selectedDate: Date = Date()
    @State private var showFullDatePicker: Bool = false
    @State private var caregiverBoardFilter: String = "ALL"

    init(loginVM: LoginViewModel) {
        self.loginVM = loginVM
        _viewModel = StateObject(wrappedValue: DailyNoteViewModel(loginVM: loginVM))
    }

    /// 留言板雙欄網格佈局
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// 判斷當前使用者是否為照護者角色 (role == 1)
    private var isCaregiver: Bool { loginVM.userData?.role == 1 }

    /// 依選取日期過濾之心情紀錄列表
    private var filteredMoods: [DailyNote] {
        viewModel.todaysDailiesWithMood.filter {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    /// 依選取日期與權限過濾之留言便籤列表
    private var filteredNotes: [DailyNote] {
        viewModel.notes.filter { note in
            let isSameDay = Calendar.current.isDate(
                note.date,
                inSameDayAs: selectedDate
            )
            let hasContent = !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isAccessible =
                isCaregiver
                ? (caregiverBoardFilter == "CAREGIVER_ONLY"
                    ? (note.isCaregiverOnly ?? false) : true)
                : !(note.isCaregiverOnly ?? false)
            return isSameDay && hasContent && isAccessible
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.98)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("心情留言板")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.horizontal, 15)
                        .padding(.top, 5)

                    compactWeekCalendarSection
                    moodSection
                    boardSection
                }
                .padding(.vertical, 12)
            }
            .refreshable {
                await reloadData(isSilent: true)
            }
            .blur(radius: viewModel.selectedDetailNote != nil ? 4 : 0)

            // 便利貼詳細內容彈窗
            if let note = viewModel.selectedDetailNote {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedDetailNote = nil
                        }
                    }

                DailyNoteDetailPopup(
                    item: note,
                    viewModel: viewModel,
                    modelContext: modelContext
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $viewModel.showAddNoteSheet) {
            AddDailyNoteSheet(
                viewModel: viewModel,
                loginVM: loginVM,
                modelContext: modelContext
            )
        }
        .sheet(item: $viewModel.editingNote) { _ in
            EditDailyNoteSheet(
                viewModel: viewModel,
                loginVM: loginVM,
                modelContext: modelContext
            )
        }
        .sheet(isPresented: $showFullDatePicker) {
            VStack {
                HStack {
                    Text("選擇日期")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button("完成") { showFullDatePicker = false }
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding()

                DatePicker(
                    "選擇日期",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Spacer()
            }
            .presentationDetents([.height(460)])
        }
        .task {
            await reloadData(isSilent: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await reloadData(isSilent: true)
            }
        }
    }

    /// 週日曆區塊
    private var compactWeekCalendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.toString(format: "yyyy 年 M 月"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                Spacer()

                Button {
                    Task { await reloadData(isSilent: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 6) {
                ForEach(currentWeekDays(for: selectedDate), id: \.self) { date in
                    let isSelected = Calendar.current.isDate(
                        date,
                        inSameDayAs: selectedDate
                    )
                    let isToday = Calendar.current.isDateInToday(date)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = date
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(weekdayString(for: date))
                                .font(.system(size: 11))
                                .foregroundColor(isSelected ? .white : .gray)

                            Text(date.toString(format: "d"))
                                .font(
                                    .system(
                                        size: 16,
                                        weight: isSelected ? .bold : .semibold
                                    )
                                )
                                .foregroundColor(
                                    isSelected
                                        ? .white
                                        : (isToday
                                            ? Color(
                                                red: 0.1,
                                                green: 0.45,
                                                blue: 0.85
                                            ) : .primary)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected
                                ? Color(red: 0.25, green: 0.52, blue: 0.95)
                                : Color.white
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showFullDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(
                            Color(red: 0.25, green: 0.52, blue: 0.95)
                        )
                        .frame(width: 38, height: 50)
                        .background(
                            Color(red: 0.25, green: 0.52, blue: 0.95)
                                .opacity(0.1)
                        )
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 心情展示區塊
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                Calendar.current.isDateInToday(selectedDate)
                    ? "今天心情：" : "\(selectedDate.toString(format: "MM/dd")) 心情："
            )
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))

            if filteredMoods.isEmpty {
                HStack {
                    Spacer()
                    Text(
                        Calendar.current.isDateInToday(selectedDate)
                            ? "今天尚未記錄心情" : "該日期尚未記錄心情"
                    )
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(filteredMoods) { daily in
                            if let moodName = daily.moodName {
                                moodItem(daily: daily, moodName: moodName)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
    }

    /// 單一心情圖示項目
    private func moodItem(daily: DailyNote, moodName: String) -> some View {
        VStack(spacing: 6) {
            Text(daily.date.toString(format: "HH:mm"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            Image(systemName: viewModel.getMoodIcon(for: moodName))
                .font(.system(size: 26))

            Text(moodName)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(width: 72)
        .padding(.vertical, 12)
        .background(viewModel.getMoodColor(for: moodName).opacity(0.15))
        .foregroundColor(viewModel.getMoodColor(for: moodName))
        .cornerRadius(12)
    }

    /// 留言看板區塊
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("留言看板")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))

                Spacer()

                Button {
                    viewModel.showAddNoteSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("寫便利貼")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.25, green: 0.52, blue: 0.95))
                    .cornerRadius(16)
                }
            }

            if isCaregiver {
                Picker("看板分類", selection: $caregiverBoardFilter) {
                    Text("全部留言").tag("ALL")
                    Text("僅限家屬查看").tag("CAREGIVER_ONLY")
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 2)
            }

            if viewModel.isLoadingData {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if filteredNotes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.5))

                    Text("該日期無留言紀錄")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredNotes) { note in
                        DailyNoteCardView(item: note, viewModel: viewModel)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.selectedDetailNote = note
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 重新載入心情與留言資料
    private func reloadData(isSilent: Bool = false) async {
        await viewModel.loadAllNotes(
            modelContext: modelContext,
            isSilent: isSilent
        )
    }

    /// 取得目標日期所在週的 7 天日期陣列
    private func currentWeekDays(for date: Date) -> [Date] {
        let calendar = Calendar.current
        guard
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date)
        else { return [] }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekInterval.start)
        }
    }

    /// 格式化星期字串 (例：週一)
    private func weekdayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// 留言便籤卡片視圖
struct DailyNoteCardView: View {
    let item: DailyNote
    @ObservedObject var viewModel: DailyNoteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let moodName = item.moodName, !moodName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.getMoodIcon(for: moodName))
                        Text(moodName)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                }

                Spacer()

                if item.isCaregiverOnly == true {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                        Text("家屬")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.gray)
                    .cornerRadius(4)
                }
            }

            Text(item.content)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)

            Spacer()

            HStack {
                Text(item.sender)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        item.sender == viewModel.currentUserRole
                            ? Color.orange.opacity(0.15)
                            : Color.blue.opacity(0.15)
                    )
                    .foregroundColor(
                        item.sender == viewModel.currentUserRole
                            ? .orange : .blue
                    )
                    .cornerRadius(4)

                Spacer()

                Text(item.date.toString(format: "MM/dd HH:mm"))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .frame(minHeight: 130, maxHeight: 180, alignment: .topLeading)
        .background(Color(hex: item.colorHex))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 3)
    }
}

/// 便籤詳細內容彈窗
struct DailyNoteDetailPopup: View {
    let item: DailyNote
    @ObservedObject var viewModel: DailyNoteViewModel
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.sender)
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                item.sender == viewModel.currentUserRole
                                    ? Color.orange.opacity(0.2)
                                    : Color.blue.opacity(0.2)
                            )
                            .foregroundColor(
                                item.sender == viewModel.currentUserRole
                                    ? .orange : .blue
                            )
                            .cornerRadius(6)

                        if item.isCaregiverOnly == true {
                            Text("僅照護者家屬")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.gray)
                                .cornerRadius(4)
                        }
                    }

                    Text(item.date.toString(format: "MM/dd HH:mm"))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                if let moodName = item.moodName, !moodName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.getMoodIcon(for: moodName))
                        Text(moodName)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                }
            }

            Divider()

            ScrollView {
                Text(item.content)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            /// 操作按鈕 (僅限本人發送之便籤)
            if item.sender == viewModel.currentUserRole {
                HStack(spacing: 12) {
                    Button {
                        viewModel.startEditing(item)
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("編輯")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button(role: .destructive) {
                        Task {
                            withAnimation { viewModel.selectedDetailNote = nil }
                            await viewModel.deleteNote(
                                note: item,
                                modelContext: modelContext
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("刪除")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(24)
        .frame(width: 320, height: 420)
        .background(Color(hex: item.colorHex))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}

/// 新增留言貼紙工作表
struct AddDailyNoteSheet: View {
    @ObservedObject var viewModel: DailyNoteViewModel
    @ObservedObject var loginVM: LoginViewModel
    let modelContext: ModelContext

    var body: some View {
        NavigationView {
            Form {
                /// 輸入留言內文
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $viewModel.newNoteText)
                            .frame(height: 200)
                            .onChange(of: viewModel.newNoteText) { _, newValue in
                                viewModel.handleNoteTextChange(newValue)
                            }

                        Text("\(viewModel.newNoteText.count) / 100")
                            .font(.system(size: 12))
                            .foregroundColor(
                                viewModel.newNoteText.count >= 100
                                    ? .red : .gray
                            )
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                    }
                } header: {
                    Text(viewModel.isPatient ? "留言內容 (選填，可僅記錄心情)" : "留言內容 (必填)")
                } footer: {
                    SpeechTipBanner()
                        .listRowInsets(
                            EdgeInsets(
                                top: 12,
                                leading: 0,
                                bottom: 20,
                                trailing: 0
                            )
                        )
                }

                if loginVM.userData?.role == 1 {
                    Section(header: Text("是否要讓 \(loginVM.partnerName) 看到這則便利貼")) {
                        Toggle(isOn: $viewModel.isCaregiverOnly) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.blue)
                                Text("僅限照護者家屬查看")
                            }
                        }
                    }
                }

                if loginVM.userData?.role == 0 {
                    Section(header: Text("記錄當下心情 (可單獨記錄)")) {
                        MoodPickerView(
                            moods: viewModel.moods,
                            selectedMood: $viewModel.sheetSelectedMoodName,
                            getMoodIcon: { viewModel.getMoodIcon(for: $0) },
                            getMoodColor: { viewModel.getMoodColor(for: $0) }
                        )
                    }
                }

                Section(header: Text("選擇貼紙顏色")) {
                    HStack(spacing: 16) {
                        ColorPickerButton(
                            color: Color(red: 1.0, green: 0.94, blue: 0.8),
                            selectedColor: $viewModel.noteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.9, green: 0.96, blue: 1.0),
                            selectedColor: $viewModel.noteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.92, green: 0.98, blue: 0.93),
                            selectedColor: $viewModel.noteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.98, green: 0.92, blue: 0.95),
                            selectedColor: $viewModel.noteColor
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新增留言貼紙")
            .navigationBarItems(
                leading: Button("取消") {
                    hideKeyboard()
                    viewModel.cancelAddingNote()
                },
                trailing: Button("發送") {
                    hideKeyboard()
                    Task {
                        await viewModel.sendNote(modelContext: modelContext)
                    }
                }
                .disabled(!viewModel.canSendNote)
            )
        }
    }
}

/// 編輯留言貼紙工作表
struct EditDailyNoteSheet: View {
    @ObservedObject var viewModel: DailyNoteViewModel
    @ObservedObject var loginVM: LoginViewModel
    let modelContext: ModelContext

    var body: some View {
        NavigationView {
            Form {
                /// 修改留言內文
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $viewModel.editNoteText)
                            .frame(height: 200)
                            .onChange(of: viewModel.editNoteText) { _, newValue in
                                viewModel.handleEditTextChange(newValue)
                            }

                        Text("\(viewModel.editNoteText.count) / 100")
                            .font(.system(size: 12))
                            .foregroundColor(
                                viewModel.editNoteText.count >= 100
                                    ? .red : .gray
                            )
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                    }
                } header: {
                    Text(
                        viewModel.isPatient
                            ? "修改留言內容 (選填，可僅保留心情)" : "修改留言內容 (必填)"
                    )
                } footer: {
                    SpeechTipBanner()
                        .listRowInsets(
                            EdgeInsets(
                                top: 12,
                                leading: 0,
                                bottom: 20,
                                trailing: 0
                            )
                        )
                }

                if loginVM.userData?.role == 1 {
                    Section(header: Text("是否要讓 \(loginVM.partnerName) 看到這則便利貼")) {
                        Toggle(isOn: $viewModel.editIsCaregiverOnly) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.blue)
                                Text("僅限照護者家屬查看")
                            }
                        }
                    }
                }

                if loginVM.userData?.role == 0 {
                    Section(header: Text("調整當下心情")) {
                        MoodPickerView(
                            moods: viewModel.moods,
                            selectedMood: $viewModel.editSelectedMoodName,
                            getMoodIcon: { viewModel.getMoodIcon(for: $0) },
                            getMoodColor: { viewModel.getMoodColor(for: $0) }
                        )
                    }
                }

                Section(header: Text("修改貼紙顏色")) {
                    HStack(spacing: 16) {
                        ColorPickerButton(
                            color: Color(red: 1.0, green: 0.94, blue: 0.8),
                            selectedColor: $viewModel.editNoteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.9, green: 0.96, blue: 1.0),
                            selectedColor: $viewModel.editNoteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.92, green: 0.98, blue: 0.93),
                            selectedColor: $viewModel.editNoteColor
                        )
                        ColorPickerButton(
                            color: Color(red: 0.98, green: 0.92, blue: 0.95),
                            selectedColor: $viewModel.editNoteColor
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("編輯留言貼紙")
            .navigationBarItems(
                leading: Button("取消") {
                    hideKeyboard()
                    viewModel.editingNote = nil
                },
                trailing: Button("儲存") {
                    hideKeyboard()
                    Task {
                        await viewModel.saveEditedNote(
                            modelContext: modelContext
                        )
                    }
                }
                .disabled(!viewModel.canSaveEditedNote)
            )
        }
    }
}

/// 語音輸入提示橫幅
struct SpeechTipBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    Color(red: 0.25, green: 0.52, blue: 0.95)
                )

            Text("點擊鍵盤右下角麥克風圖示，即可直接語音轉文字輸入")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.25, green: 0.52, blue: 0.95).opacity(0.08))
        .cornerRadius(12)
    }
}

/// 心情選取元件
struct MoodPickerView: View {
    let moods: [String]
    @Binding var selectedMood: String?
    let getMoodIcon: (String) -> String
    let getMoodColor: (String) -> Color

    var body: some View {
        HStack(spacing: 12) {
            ForEach(moods, id: \.self) { moodName in
                Button {
                    selectedMood = (selectedMood == moodName) ? nil : moodName
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: getMoodIcon(moodName))
                            .font(.system(size: 26))

                        Text(moodName)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedMood == moodName
                            ? getMoodColor(moodName).opacity(0.2)
                            : Color(red: 0.96, green: 0.96, blue: 0.96)
                    )
                    .foregroundColor(
                        selectedMood == moodName
                            ? getMoodColor(moodName) : .gray
                    )
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
