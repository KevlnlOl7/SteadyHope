import SwiftData
import SwiftUI

struct DailyNoteView: View {
    @StateObject private var viewModel: DailyNoteViewModel
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

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
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("心情留言板")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
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
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Button("完成") { showFullDatePicker = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }
                .padding()

                DatePicker(
                    "選擇日期",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(AppTheme.primary(for: colorScheme))
                .padding(.horizontal)

                Spacer()
            }
            .background(AppTheme.background(for: colorScheme))
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
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.leading, 2)

                Spacer()

                Button {
                    Task { await reloadData(isSilent: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(8)
                        .background(AppTheme.cardBackground(for: colorScheme))
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
                                .foregroundColor(isSelected ? .white : AppTheme.textSecondary(for: colorScheme))

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
                                            ? AppTheme.primary(for: colorScheme)
                                            : AppTheme.textPrimary(for: colorScheme))
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected
                                ? AppTheme.primary(for: colorScheme)
                                : AppTheme.cardBackground(for: colorScheme)
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
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .frame(width: 38, height: 50)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
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
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            if filteredMoods.isEmpty {
                HStack {
                    Spacer()
                    Text(
                        Calendar.current.isDateInToday(selectedDate)
                            ? "今天尚未記錄心情" : "該日期尚未記錄心情"
                    )
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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
        let moodColor = viewModel.getMoodColor(for: moodName, colorScheme: colorScheme)
        return VStack(spacing: 6) {
            Text(daily.date.toString(format: "HH:mm"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Image(systemName: viewModel.getMoodIcon(for: moodName))
                .font(.system(size: 26))

            Text(moodName)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(width: 72)
        .padding(.vertical, 12)
        .background(
            colorScheme == .dark
                ? AppTheme.cardBackground(for: colorScheme)
                : moodColor.opacity(0.15)
        )
        .foregroundColor(moodColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke( colorScheme == .dark ? moodColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    /// 留言看板區塊
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("留言看板")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

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
                    .background(AppTheme.primary(for: colorScheme))
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
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))

                    Text("該日期無留言紀錄")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let moodName = item.moodName, !moodName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.getMoodIcon(for: moodName))
                        Text(moodName)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(
                        colorScheme == .dark
                            ? viewModel.getMoodColor(for: moodName, colorScheme: colorScheme)
                            : AppTheme.textSecondary(for: colorScheme)
                    )
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
                    .background(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "4A5568"))
                    .cornerRadius(4)
                }
            }

            Text(item.content)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "2C323A"))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)

            Spacer()

            HStack {
                Text(viewModel.senderDisplayName(for: item))
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        viewModel.isMyNote(item)
                            ? AppTheme.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.35 : 0.2)
                            : AppTheme.primary(for: colorScheme).opacity(colorScheme == .dark ? 0.3 : 0.18)
                    )
                    .foregroundColor(
                        viewModel.isMyNote(item)
                            ? AppTheme.accent(for: colorScheme)
                            : AppTheme.primary(for: colorScheme)
                    )
                    .cornerRadius(4)

                Spacer()

                Text(item.date.toString(format: "MM/dd HH:mm"))
                    .font(.system(size: 10))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color(hex: "64748B"))
            }
        }
        .padding(14)
        .frame(minHeight: 130, maxHeight: 180, alignment: .topLeading)
        .background(viewModel.getNoteCardColor(for: item.colorHex, colorScheme: colorScheme))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .softCardShadow()
    }
}

/// 便籤詳細內容彈窗
struct DailyNoteDetailPopup: View {
    let item: DailyNote
    @ObservedObject var viewModel: DailyNoteViewModel
    let modelContext: ModelContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(viewModel.senderDisplayName(for: item))
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                viewModel.isMyNote(item)
                                    ? AppTheme.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.35 : 0.2)
                                    : AppTheme.primary(for: colorScheme).opacity(colorScheme == .dark ? 0.3 : 0.18)
                            )
                            .foregroundColor(
                                viewModel.isMyNote(item)
                                    ? AppTheme.accent(for: colorScheme)
                                    : AppTheme.primary(for: colorScheme)
                            )
                            .cornerRadius(6)

                        if item.isCaregiverOnly == true {
                            Text("僅照護者家屬")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "4A5568"))
                                .cornerRadius(4)
                        }
                    }

                    Text(item.date.toString(format: "MM/dd HH:mm"))
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color(hex: "64748B"))
                }

                Spacer()

                if let moodName = item.moodName, !moodName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.getMoodIcon(for: moodName))
                        Text(moodName)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        colorScheme == .dark
                            ? viewModel.getMoodColor(for: moodName, colorScheme: colorScheme)
                            : AppTheme.textSecondary(for: colorScheme)
                    )
                }
            }

            Divider()

            ScrollView {
                Text(item.content)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "18191B"))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            /// 操作按鈕 (僅限本人發送之便籤)
            if viewModel.isMyNote(item) {
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
                    .tint(AppTheme.primary(for: colorScheme))

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
        .background(viewModel.getNoteCardColor(for: item.colorHex, colorScheme: colorScheme))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .softCardShadow()
    }
}

/// 新增留言貼紙工作表
struct AddDailyNoteSheet: View {
    @ObservedObject var viewModel: DailyNoteViewModel
    @ObservedObject var loginVM: LoginViewModel
    let modelContext: ModelContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            Form {
                /// 輸入留言內文
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $viewModel.newNoteText)
                            .frame(height: 200)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .onChange(of: viewModel.newNoteText) { _, newValue in
                                viewModel.handleNoteTextChange(newValue)
                            }

                        Text("\(viewModel.newNoteText.count) / 100")
                            .font(.system(size: 12))
                            .foregroundColor(
                                viewModel.newNoteText.count >= 100
                                    ? .red : AppTheme.textSecondary(for: colorScheme)
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
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                                Text("僅限照護者家屬查看")
                            }
                        }
                        .tint(AppTheme.primary(for: colorScheme))
                    }
                }

                if loginVM.userData?.role == 0 {
                    Section(header: Text("記錄當下心情 (可單獨記錄)")) {
                        MoodPickerView(
                            moods: viewModel.moods,
                            selectedMood: $viewModel.sheetSelectedMoodName,
                            getMoodIcon: { viewModel.getMoodIcon(for: $0) },
                            getMoodColor: { viewModel.getMoodColor(for: $0, colorScheme: colorScheme) }
                        )
                    }
                }

                Section(header: Text("選擇貼紙顏色")) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.notePalette(for: colorScheme), id: \.self) { color in
                            ColorPickerButton(
                                color: color,
                                selectedColor: $viewModel.noteColor
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("新增留言貼紙")
            .navigationBarItems(
                leading: Button("取消") {
                    hideKeyboard()
                    viewModel.cancelAddingNote()
                }
                .foregroundColor(AppTheme.primary(for: colorScheme)),
                trailing: Button("發送") {
                    hideKeyboard()
                    Task {
                        await viewModel.sendNote(modelContext: modelContext)
                    }
                }
                .foregroundColor(AppTheme.primary(for: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            Form {
                /// 修改留言內文
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $viewModel.editNoteText)
                            .frame(height: 200)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .onChange(of: viewModel.editNoteText) { _, newValue in
                                viewModel.handleEditTextChange(newValue)
                            }

                        Text("\(viewModel.editNoteText.count) / 100")
                            .font(.system(size: 12))
                            .foregroundColor(
                                viewModel.editNoteText.count >= 100
                                    ? .red : AppTheme.textSecondary(for: colorScheme)
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
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                                Text("僅限照護者家屬查看")
                            }
                        }
                        .tint(AppTheme.primary(for: colorScheme))
                    }
                }

                if loginVM.userData?.role == 0 {
                    Section(header: Text("調整當下心情")) {
                        MoodPickerView(
                            moods: viewModel.moods,
                            selectedMood: $viewModel.editSelectedMoodName,
                            getMoodIcon: { viewModel.getMoodIcon(for: $0) },
                            getMoodColor: { viewModel.getMoodColor(for: $0, colorScheme: colorScheme) }
                        )
                    }
                }

                Section(header: Text("修改貼紙顏色")) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.notePalette(for: colorScheme), id: \.self) { color in
                            ColorPickerButton(
                                color: color,
                                selectedColor: $viewModel.editNoteColor
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("編輯留言貼紙")
            .navigationBarItems(
                leading: Button("取消") {
                    hideKeyboard()
                    viewModel.editingNote = nil
                }
                .foregroundColor(AppTheme.primary(for: colorScheme)),
                trailing: Button("儲存") {
                    hideKeyboard()
                    Task {
                        await viewModel.saveEditedNote(
                            modelContext: modelContext
                        )
                    }
                }
                .foregroundColor(AppTheme.primary(for: colorScheme))
                .disabled(!viewModel.canSaveEditedNote)
            )
        }
    }
}

/// 語音輸入提示橫幅
struct SpeechTipBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            Text("點擊鍵盤右下角麥克風圖示，即可直接語音轉文字輸入")
                .font(.system(size: 12.5))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(AppTheme.primary(for: colorScheme).opacity(0.08))
        .cornerRadius(12)
    }
}

/// 心情選取元件
struct MoodPickerView: View {
    let moods: [String]
    @Binding var selectedMood: String?
    let getMoodIcon: (String) -> String
    let getMoodColor: (String) -> Color
    @Environment(\.colorScheme) private var colorScheme

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
                            : AppTheme.background(for: colorScheme)
                    )
                    .foregroundColor(
                        selectedMood == moodName
                            ? getMoodColor(moodName) : AppTheme.textSecondary(for: colorScheme)
                    )
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
