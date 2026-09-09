import SwiftUI

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = AIChatViewModel.shared
    @State private var showDatePicker: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.isSearching {
                        searchBarHeader
                            .transition(
                                .move(edge: .top).combined(with: .opacity)
                            )
                    }

                    chatMessageScrollView

                    if viewModel.isSearching {
                        searchNavigationToolbar
                            .transition(
                                .move(edge: .bottom).combined(with: .opacity)
                            )
                    } else {
                        bottomInputSection
                    }
                }
            }
            .navigationTitle(viewModel.isSearching ? "" : "小安")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(viewModel.isSearching)
            .toolbar {
                if !viewModel.isSearching {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("關閉") {
                            dismiss()
                        }
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .fontWeight(.medium)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(
                                .spring(response: 0.3, dampingFraction: 0.8)
                            ) {
                                viewModel.isSearching = true
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(
                                    AppTheme.primary(for: colorScheme)
                                )
                        }
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .alert(
                "溫馨提醒",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // 初次進入畫面時非同步載入歷史對話紀錄
            .task {
                viewModel.loadHistory()
            }
        }
    }
}

extension AIChatView {

    /// 頂部訊息搜尋列（輸入框、清除按鈕與退出搜尋按鈕）
    fileprivate var searchBarHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body)

                TextField("搜尋訊息...", text: $viewModel.searchText)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .font(.body)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.background(for: colorScheme))
            .cornerRadius(20)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.isSearching = false
                    viewModel.clearFilter()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            AppTheme.cardBackground(for: colorScheme)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 2)
                .ignoresSafeArea(edges: .top)
        )
    }

    /// 搜尋狀態下底部關鍵字導覽工具列
    fileprivate var searchNavigationToolbar: some View {
        HStack {
            HStack(spacing: 16) {
                Button {
                    viewModel.previousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(
                            viewModel.matchedMessages.isEmpty
                                ? .gray.opacity(0.4)
                                : AppTheme.primary(for: colorScheme)
                        )
                }
                .disabled(viewModel.matchedMessages.isEmpty)

                Button {
                    viewModel.nextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(
                            viewModel.matchedMessages.isEmpty
                                ? .gray.opacity(0.4)
                                : AppTheme.primary(for: colorScheme)
                        )
                }
                .disabled(viewModel.matchedMessages.isEmpty)

                if !viewModel.matchedMessages.isEmpty {
                    Text(
                        "\(viewModel.currentSearchIndex + 1) / \(viewModel.matchedMessages.count)"
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                if viewModel.selectedDate != nil {
                    viewModel.selectedDate = nil
                } else {
                    showDatePicker.toggle()
                }
            } label: {
                Image(
                    systemName: viewModel.selectedDate != nil
                        ? "xmark.circle.fill" : "calendar"
                )
                .font(.title2)
                .foregroundColor(
                    viewModel.selectedDate != nil
                        ? .red : AppTheme.primary(for: colorScheme)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            AppTheme.cardBackground(for: colorScheme)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// 對話訊息歷史 ScrollView 容器
    fileprivate var chatMessageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isLoadingHistory {
                    ProgressView()
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .scaleEffect(0.9)
                }

                if viewModel.filteredMessages.isEmpty && !viewModel.isLoading
                    && !viewModel.isLoadingHistory
                {
                    emptyStatePlaceholder
                } else {
                    LazyVStack(spacing: 10) {
                        // 依日期區塊分組渲染訊息
                        ForEach(viewModel.groupedMessages) { group in
                            Section(header: DateHeaderView(date: group.date)) {
                                ForEach(group.messages) { message in
                                    let isCurrent =
                                        message.id
                                        == viewModel.currentMatchMessageId
                                    ChatBubble(
                                        message: message,
                                        highlightText: viewModel.searchText,
                                        isCurrentMatch: isCurrent
                                    )
                                    .id("\(message.id)_\(isCurrent)")
                                }
                            }
                        }

                        if viewModel.isLoading {
                            loadingBubble
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation {
                        proxy.scrollTo("loading_bubble", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentSearchIndex) { _, _ in
                if let targetId = viewModel.currentMatchMessageId {
                    withAnimation(.spring()) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }

    /// 無訊息時顯示的預設健康導引畫面
    fileprivate var emptyStatePlaceholder: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.primary(for: colorScheme).opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 42))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }

            Text("今天身體感覺怎麼樣呢？")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("不論是想聊聊或詢問健康問題，\n我都隨時在這裡陪您喔！")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(
                    AppTheme.textPrimary(for: colorScheme).opacity(0.6)
                )
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, 32)
    }

    /// AI 思考與生成回答中之載入指示氣泡
    fileprivate var loadingBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundColor(AppTheme.accent(for: colorScheme))
                .font(.system(size: 18))

            Text("小安正在認真想答案喔...")
                .font(.footnote)
                .foregroundColor(
                    AppTheme.textPrimary(for: colorScheme).opacity(0.7)
                )

            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .id("loading_bubble")
    }

    /// 一般模式下之底部文字輸入框與衛教警語區塊
    fileprivate var bottomInputSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    "問問小安健康小知識...",
                    text: $viewModel.inputText,
                    axis: .vertical
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.background(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(24)
                .lineLimit(1...4)
                .disabled(viewModel.isLoading)

                actionButton
            }

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundColor(AppTheme.accent(for: colorScheme))
                Text("小安提供的資訊僅供衛教參考，無法取代專業醫療診斷。\n若有任何症狀或用藥問題，請務必諮詢您的主治醫師。")
                    .font(.caption2)
                    .foregroundColor(
                        AppTheme.textPrimary(for: colorScheme).opacity(0.6)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(bottomInputBackground)
    }

    /// 底部輸入區塊之圓角卡片背景造型
    fileprivate var bottomInputBackground: some View {
        AppTheme.cardBackground(for: colorScheme)
            .clipShape(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -3)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    /// 發送與中斷生成之操作按鈕
    @ViewBuilder
    fileprivate var actionButton: some View {
        let isTextEmpty = viewModel.inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty

        if viewModel.isLoading {
            Button {
                viewModel.stopGeneration()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(13)
                    .background(AppTheme.accent(for: colorScheme))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        } else {
            Button {
                viewModel.sendMessage()
            } label: {
                let btnColor =
                    isTextEmpty
                    ? Color.gray.opacity(0.4)
                    : AppTheme.accent(for: colorScheme)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(btnColor)
                    .clipShape(Circle())
                    .shadow(
                        color: AppTheme.accent(for: colorScheme).opacity(0.3),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
            .disabled(isTextEmpty)
        }
    }

    /// 選擇對話日期之彈窗視圖
    fileprivate var datePickerSheet: some View {
        VStack(spacing: 16) {
            Text("選擇對話日期")
                .font(.headline)
                .padding(.top, 16)

            DatePicker(
                "選擇搜尋日期",
                selection: Binding(
                    get: { viewModel.selectedDate ?? Date() },
                    set: { newDate in
                        if viewModel.hasMessages(on: newDate) {
                            viewModel.selectedDate = newDate
                        } else {
                            viewModel.errorMessage = "該日期沒有對話紀錄喔！"
                        }
                    }
                ),
                in: viewModel.selectableDateRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)

            Button {
                showDatePicker = false
            } label: {
                Text("確定")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary(for: colorScheme))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .presentationDetents([.height(480)])
    }

    /// 自動將 ScrollView 捲動至最底部或指定載入區域
    /// - Parameter proxy: 捲動控制視圖代理
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isLoading {
            withAnimation(.spring()) {
                proxy.scrollTo("loading_bubble", anchor: .bottom)
            }
        } else if let lastMessage = viewModel.filteredMessages.last {
            withAnimation(.spring()) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

/// 日期分頁標籤視圖
struct DateHeaderView: View {
    /// 當前分組所屬日期
    let date: Date

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(dateString(for: date))
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(
                AppTheme.textPrimary(for: colorScheme).opacity(0.6)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(AppTheme.textPrimary(for: colorScheme).opacity(0.08))
            )
    }
}

/// 對話氣泡視圖
struct ChatBubble: View {
    
    /// 該氣泡呈現之訊息模型
    let message: ChatMessage

    /// 當前搜尋之高亮關鍵字
    let highlightText: String

    /// 此訊息是否為當前搜尋導覽選中之目標
    let isCurrentMatch: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // 使用者發送之訊息（靠右對齊，時間置於氣泡左側）
            if message.isUser {
                Spacer(minLength: 40)

                // 訊息發送時間
                Text(message.timestamp.toString(format: "HH:mm"))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // 使用者對話氣泡
                Text(message.text)
                    .font(.body)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(AppTheme.primary(for: colorScheme))
                    .cornerRadius(20)
                    .shadow(
                        color: AppTheme.primary(for: colorScheme).opacity(0.2),
                        radius: 5,
                        x: 0,
                        y: 2
                    )

            // AI 小安回覆之訊息（靠左對齊，包含頭像、名稱、時間置於氣泡右側）
            } else {
                // 小安大頭貼
                ZStack {
                    Circle()
                        .fill(AppTheme.primary(for: colorScheme).opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }
                .alignmentGuide(.bottom) { d in d[.bottom] + 18 }

                VStack(alignment: .leading, spacing: 4) {
                    Text("小安")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(
                            AppTheme.textPrimary(for: colorScheme).opacity(0.6)
                        )
                        .padding(.leading, 4)

                    // 支援 Markdown 與關鍵字高亮之回覆內文
                    HighlightText(
                        text: message.text,
                        highlight: isCurrentMatch ? highlightText : "",
                        highlightColor: .orange,
                        isUser: false
                    )
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(20)
                    .shadow(
                        color: .black.opacity(0.04),
                        radius: 5,
                        x: 0,
                        y: 2
                    )
                }
                .frame(
                    maxWidth: UIScreen.main.bounds.width * 0.78,
                    alignment: .leading
                )

                Text(message.timestamp.toString(format: "HH:mm"))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer(minLength: 16)
            }
        }
        .padding(.horizontal, 12)
    }
}

/// 支援動態關鍵字高亮與 Markdown（標題、清單符號、粗體）解析之 Text 元件
struct HighlightText: View {
    
    /// 原始文字內容
    let text: String
    
    /// 欲高亮之目標字串
    let highlight: String
    
    /// 高亮之背景顏色
    let highlightColor: Color
    
    /// 是否為使用者所發送
    let isUser: Bool

    var body: some View {
        // 將逸出換行字元還原並切分為逐行陣列
        let rawText = text.replacingOccurrences(of: "\\n", with: "\n")
        let lines = rawText.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<lines.count, id: \.self) { index in
                let line = lines[index]
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                if trimmedLine.isEmpty {
                    // 空行佔位間距
                    Color.clear.frame(height: 2)
                } else if trimmedLine.hasPrefix("###") {
                    // 三級標題解析
                    let cleanLine = trimmedLine.replacingOccurrences(
                        of: "###",
                        with: ""
                    ).trimmingCharacters(in: .whitespaces)

                    Text(parseInlineAndHighlight(cleanLine))
                        .font(.title3.bold())
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                } else if trimmedLine.hasPrefix("-") {
                    // 無序清單項目解析（支援層級縮排與自定義圓點）
                    if let dashRange = line.range(of: "-") {
                        let leadingSpaceCount = line.distance(
                            from: line.startIndex,
                            to: dashRange.lowerBound
                        )
                        let cleanLine = String(line[dashRange.upperBound...])
                            .trimmingCharacters(in: .whitespaces)

                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.title)
                                .frame(height: 16)

                            Text(parseInlineAndHighlight(cleanLine))
                        }
                        .padding(.leading, leadingSpaceCount > 0 ? 24 : 4)
                    }
                } else {
                    // 一般文字行
                    Text(parseInlineAndHighlight(trimmedLine))
                }
            }
        }
    }

    /// 負責處理 Markdown 行內語法（如粗體）與搜尋關鍵字背景高亮的解析器
    /// - Parameter string: 欲解析的單行純文字字串
    /// - Returns: 套用樣式與高亮後的 AttributedString
    private func parseInlineAndHighlight(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        var attr =
            (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)

        let trimmedHighlight = highlight.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedHighlight.isEmpty {
            var searchRange: Range<AttributedString.Index>? =
                attr.startIndex..<attr.endIndex

            // 迴圈比對所有符合關鍵字的範圍並套用背景色
            while let currentRange = searchRange,
                let matchRange = attr[currentRange].range(
                    of: trimmedHighlight,
                    options: .caseInsensitive
                )
            {
                attr[matchRange].backgroundColor = highlightColor.opacity(0.35)
                attr[matchRange].foregroundColor = isUser ? .white : .primary

                if matchRange.upperBound < attr.endIndex {
                    searchRange = matchRange.upperBound..<attr.endIndex
                } else {
                    searchRange = nil
                }
            }
        }
        return attr
    }
}

/// 動態日期轉換輔助函式
/// - Parameter date: 欲格式化之日期物件
/// - Returns: 相對應之顯示字串（例如：「今天」、「昨天」或完整日期格式）
private func dateString(for date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
        return "今天"
    }

    if calendar.isDateInYesterday(date) {
        return "昨天"
    }

    let now = Date()
    let isSameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)

    if isSameYear {
        return date.toString(format: "M/d(EEE)")
    } else {
        return date.toString(format: "yyyy年M月d日 EEE")
    }
}
