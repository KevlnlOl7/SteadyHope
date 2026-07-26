import AVFoundation
import Combine
import Speech
import SwiftData
import SwiftUI

struct DailyView: View {
    @StateObject private var viewModel: DailyViewModel
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.modelContext) private var modelContext

    /// 初始化照護看板視圖並配置對應的 ViewModel
    /// - Parameter loginVM: 包含目前使用者登入狀態與角色權限的 LoginViewModel
    init(loginVM: LoginViewModel) {
        self.loginVM = loginVM
        _viewModel = StateObject(
            wrappedValue: DailyViewModel(loginVM: loginVM)
        )
    }

    /// 留言板便利貼卡片之雙欄網格佈局
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("心情留言板")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.top, 5)

                    // 今日心情歷程區塊
                    moodSection

                    // 便利貼留言看板區塊
                    boardSection
                }
                .padding(.vertical)
            }
            .onDisappear {
                viewModel.selectedDetailNote = nil
            }
            .background(
                Color(red: 0.97, green: 0.97, blue: 0.97).ignoresSafeArea()
            )
            .blur(radius: viewModel.selectedDetailNote != nil ? 4 : 0)
            .task {
                // 畫面載入時自動同步伺服器並拉取最新看板留言
                await viewModel.loadAllNotes(modelContext: modelContext)
            }

            // 置中放大的便利貼詳細資訊彈窗
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
    }

    /// 今日心情顯示區塊
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天心情：")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))

            if viewModel.todaysDailiesWithMood.isEmpty {
                Text("今天尚未記錄心情")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.todaysDailiesWithMood) { daily in
                            if let moodName = daily.moodName {
                                moodItem(daily: daily, moodName: moodName)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    /// 單一心情圖示項目
    private func moodItem(daily: Daily, moodName: String) -> some View {
        VStack(spacing: 8) {
            Text(daily.date.toString(format: "MM/dd HH:mm"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            Image(systemName: viewModel.getMoodIcon(for: moodName))
                .font(.system(size: 26))

            Text(moodName)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(width: 85)
        .padding(.vertical, 12)
        .background(
            viewModel.getMoodColor(for: moodName).opacity(0.2)
        )
        .foregroundColor(viewModel.getMoodColor(for: moodName))
        .cornerRadius(16)
    }

    /// 便利貼留言看板區塊
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("留言板")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                Spacer()

                Button(action: {
                    viewModel.showAddNoteSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("寫便利貼")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0, green: 0.53, blue: 1))
                    .cornerRadius(20)
                }
            }

            if viewModel.isLoadingData {
                HStack {
                    Spacer()
                    ProgressView("讀取看板中...")
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.notes) { note in
                        DailyNoteCardView(item: note, viewModel: viewModel)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedDetailNote = note
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

/// 網格列表中單張便利貼小卡片元件
struct DailyNoteCardView: View {
    let item: Daily
    @ObservedObject var viewModel: DailyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let moodName = item.moodName, !moodName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.getMoodIcon(for: moodName))
                    Text(moodName)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
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

/// 放大的便利貼卡片詳細資訊彈窗元件（包含刪除按鈕）
struct DailyNoteDetailPopup: View {
    let item: Daily
    @ObservedObject var viewModel: DailyViewModel
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
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

            // 僅允許發送者刪除屬於自己的便利貼
            if item.sender == viewModel.currentUserRole {
                Button(role: .destructive) {
                    Task {
                        withAnimation {
                            viewModel.selectedDetailNote = nil
                        }
                        await viewModel.deleteNote(
                            note: item,
                            modelContext: modelContext
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("刪除便利貼")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .cornerRadius(12)
            }
        }
        .padding(24)
        .frame(width: 320, height: 420)
        .background(Color(hex: item.colorHex))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}

/// 新增留言便利貼的 Sheet 視圖表單
struct AddDailyNoteSheet: View {
    @ObservedObject var viewModel: DailyViewModel
    @ObservedObject var loginVM: LoginViewModel
    let modelContext: ModelContext

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("留言內容")) {
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
                }

                HStack {
                    Spacer()
                    Button(action: {
                        if viewModel.speechRecognizer.isRecording {
                            viewModel.speechRecognizer.stopRecording()
                        } else {
                            viewModel.speechRecognizer.startRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(
                                systemName: viewModel.speechRecognizer
                                    .isRecording
                                    ? "stop.circle.fill" : "mic.circle.fill"
                            )
                            .font(.system(size: 25))
                            Text(
                                viewModel.speechRecognizer.isRecording
                                    ? "錄音中..." : "語音輸入"
                            )
                            .font(.system(size: 23, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0, green: 0.53, blue: 1))
                        .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: -10, leading: 4, bottom: 0, trailing: 4)
                )

                if loginVM.userData?.role == 0 {
                    Section(header: Text("記錄當下心情 (選填)")) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.moods, id: \.self) { moodName in
                                Button(action: {
                                    if viewModel.sheetSelectedMoodName
                                        == moodName
                                    {
                                        viewModel.sheetSelectedMoodName = nil
                                    } else {
                                        viewModel.sheetSelectedMoodName =
                                            moodName
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        Image(
                                            systemName: viewModel.getMoodIcon(
                                                for: moodName
                                            )
                                        )
                                        .font(.system(size: 26))
                                        Text(moodName)
                                            .font(
                                                .system(
                                                    size: 12,
                                                    weight: .medium
                                                )
                                            )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        viewModel.sheetSelectedMoodName
                                            == moodName
                                            ? viewModel.getMoodColor(
                                                for: moodName
                                            ).opacity(0.2)
                                            : Color(
                                                red: 0.96,
                                                green: 0.96,
                                                blue: 0.96
                                            )
                                    )
                                    .foregroundColor(
                                        viewModel.sheetSelectedMoodName
                                            == moodName
                                            ? viewModel.getMoodColor(
                                                for: moodName
                                            )
                                            : .gray
                                    )
                                    .cornerRadius(16)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 6)
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
            )
        }
    }
}
