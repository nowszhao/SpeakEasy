import SwiftUI

// 在文件顶部添加 FilterType 枚举定义
enum FilterType: String, CaseIterable {
    case all = "全部"
    case recent = "最近阅读"
    case unreadOnly = "未读"
}

// 在文件顶部添加，FilterType 枚举之前
struct TextDifference {
    let text: String
    let isMatch: Bool
    let startIndex: Int
    let endIndex: Int
}

func findDifferences(original: String, recognized: String) -> (original: [TextDifference], recognized: [TextDifference]) {
    let originalChars = Array(original)
    let recognizedChars = Array(recognized)
    
    let m = originalChars.count
    let n = recognizedChars.count
    
    // 动态规划表
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    
    // 填充 DP 表
    for i in 1...m {
        for j in 1...n {
            if originalChars[i - 1] == recognizedChars[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }
    
    // 回溯找出 LCS
    var lcs: [Character] = []
    var i = m, j = n
    while i > 0 && j > 0 {
        if originalChars[i - 1] == recognizedChars[j - 1] {
            lcs.insert(originalChars[i - 1], at: 0)
            i -= 1
            j -= 1
        } else if dp[i - 1][j] > dp[i][j - 1] {
            i -= 1
        } else {
            j -= 1
        }
    }
    
    // 标记不匹配的字符
    var originalDiffs: [TextDifference] = []
    var lcsIndex = 0
    var currentMismatch = ""
    var startIndex = 0
    
    for (index, char) in originalChars.enumerated() {
        if lcsIndex < lcs.count && char == lcs[lcsIndex] {
            if !currentMismatch.isEmpty {
                originalDiffs.append(TextDifference(
                    text: currentMismatch,
                    isMatch: false,
                    startIndex: startIndex,
                    endIndex: index
                ))
                currentMismatch = ""
            }
            originalDiffs.append(TextDifference(
                text: String(char),
                isMatch: true,
                startIndex: index,
                endIndex: index + 1
            ))
            lcsIndex += 1
        } else {
            if currentMismatch.isEmpty {
                startIndex = index
            }
            currentMismatch.append(char)
        }
    }
    
    if !currentMismatch.isEmpty {
        originalDiffs.append(TextDifference(
            text: currentMismatch,
            isMatch: false,
            startIndex: startIndex,
            endIndex: originalChars.count
        ))
    }
    
    // 识别文本的差异标记
    let recognizedDiffs = recognizedChars.map { char in
        TextDifference(text: String(char), isMatch: true, startIndex: 0, endIndex: 1)
    }
    
    return (originalDiffs, recognizedDiffs)
}

struct ContentView: View {
    var body: some View {
        NavigationView {
            TopicListView()
        }
    }
}

struct PracticeListView: View {
    let topicId: Int
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var searchText = ""
    @State private var selectedFilter: FilterType = .all
    @State private var isLoading = false
    @State private var showLoadingOverlay = false
    
    var filteredItems: [PracticeItem] {
        // 首先过滤当前专题的练习题
        let topicItems = dbManager.practiceItems
        
        // 然后应用搜索过滤
        let searchFiltered = topicItems.filter { item in
            searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText)
        }
        
        // 最后应用类型过滤
        switch selectedFilter {
        case .all:
            return searchFiltered
        case .recent:
            return searchFiltered  // 数据库层面已经过滤
        case .unreadOnly:
            return searchFiltered.filter { !($0.isRead ?? false) }
        }
    }
    
    var body: some View {
        ZStack {
            List(filteredItems) { item in
                NavigationLink {
                    PracticeRoomView(item: item)
                } label: {
                    PracticeItemRow(item: item)
                }
            }
            .navigationTitle("口语练习")
            .searchable(text: $searchText, prompt: "搜索练习")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("筛选方式", selection: $selectedFilter) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("全部")
                            }
                            .tag(FilterType.all)
                            
                            HStack {
                                Image(systemName: "clock")
                                Text("最近阅读")
                            }
                            .tag(FilterType.recent)
                            
                            HStack {
                                Image(systemName: "book.closed")
                                Text("未读")
                            }
                            .tag(FilterType.unreadOnly)
                        }
                    } label: {
                        Image(systemName: getFilterIcon())
                    }
                }
            }
            
            if showLoadingOverlay {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("加载中...")
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            dbManager.currentTopicId = topicId
            print("🎬 PracticeListView 出现")
            Task {
                showLoadingOverlay = true
                await loadItems(filter: selectedFilter)
            }
        }
        .onChange(of: selectedFilter) { newFilter in
            print("🔄 过滤模式改变: \(newFilter)")
            Task {
                showLoadingOverlay = true
                await loadItems(filter: newFilter)
            }
        }
    }
    
    private func getFilterIcon() -> String {
        switch selectedFilter {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .recent:
            return "clock"
        case .unreadOnly:
            return "book.closed"
        }
    }
    
    private func loadItems(filter: FilterType) async {
        isLoading = true
        showLoadingOverlay = true
        
        await Task.yield()
        
        await MainActor.run {
            switch filter {
            case .all, .unreadOnly:
                dbManager.loadPracticeItems(filter: .all)
            case .recent:
                dbManager.loadPracticeItems(filter: .recent)
            }
        }
        
        // 添加小延迟以确保加载动画���畅
        if !isLoading {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        await MainActor.run {
            isLoading = false
            withAnimation {
                showLoadingOverlay = false
            }
        }
    }
}

// 添加 PracticeRoomView
struct PracticeRoomView: View {
    let item: PracticeItem
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var selectedTab = 0
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ArticleView(item: item)
                .tabItem {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.title2)
                        Text("文章")
                            .font(.headline)
                    }
                }
                .tag(0)
            
            RecordingsView(recordings: dbManager.recordings)
                .tabItem {
                    VStack {
                        Image(systemName: "waveform")
                            .font(.title2)
                        Text("历史记录")
                            .font(.headline)
                    }
                }
                .tag(1)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let id = item.id {
                dbManager.loadRecordings(for: id)
            }
            
            // 设置标签栏的外观
            UITabBar.appearance().backgroundColor = .systemBackground
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            
            // 置标签字体大小
            UITabBarItem.appearance().setTitleTextAttributes([
                .font: UIFont.systemFont(ofSize: 16, weight: .medium)
            ], for: .normal)
        }
        .interactiveDismissDisabled()
    }
}

// 添加 PracticeItemRow
struct PracticeItemRow: View {
    let item: PracticeItem
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var highestScore: Int = 0
    @State private var practiceCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                if item.isRead ?? false {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                if highestScore > 0 {
                    Text("最高分: \(highestScore)")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("未练习")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                    Text("\(practiceCount)次")
                }
                .font(.caption)
                .padding(4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)
            }
        }
        .onAppear {
            loadStats()
        }
    }
    
    private func loadStats() {
        if let id = item.id {
            let stats = dbManager.loadPracticeStats(for: id)
            self.practiceCount = stats.practiceCount
            self.highestScore = stats.highestScore
        }
    }
}

// 添加 ArticleView
struct ArticleView: View {
    let item: PracticeItem
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    var body: some View {
        VStack {
            ScrollView {
                Text(item.content)
                    .padding()
            }
            
            Button(action: {
                if audioManager.isPlaying {
                    audioManager.stopPlaying()
                } else {
                    audioManager.playStreamingAudio(url: item.mp3Url)
                }
            }) {
                HStack {
                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                    Text(audioManager.isPlaying ? "暂停示范" : "播放示范")
                }
                .foregroundColor(.blue)
                .padding()
            }
            
            Divider()
            
            RecordButton(item: item)
                .frame(height: 100)
                .padding(.bottom)
        }
    }
}

// 添加 RecordingsView
struct RecordingsView: View {
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    let recordings: [Recording]
    
    var body: some View {
        List {
            ForEach(recordings) { recording in
                RecordingRow(recording: recording)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    dbManager.deleteRecording(recordings[index])
                }
            }
        }
    }
}

// 添加 RecordButton
struct RecordButton: View {
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    @StateObject private var speechRecognizer = SpeechRecognizer()
    let item: PracticeItem
    
    // 手势状态
    @State private var isRecording = false
    @State private var dragOffset: CGSize = .zero
    @State private var recordingStartTime: Date?
    @State private var recordingURL: URL?
    
    // 拖动阈值
    let cancelThreshold: CGFloat = -100  // 左滑取消
    let completeThreshold: CGFloat = 100 // 右滑完成
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                // 左侧消指示
                if isRecording {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red.opacity(
                            dragOffset.width < 0 ? 
                            min(1.0, abs(dragOffset.width) / abs(cancelThreshold)) : 0.3
                        ))
                        .frame(width: 44)
                        .animation(.easeOut, value: dragOffset)
                }
                
                Spacer()
                
                VStack {
                    // 录音状态提示
                    if isRecording {
                        Text(
                            dragOffset.width < cancelThreshold ? "松开取消" :
                            dragOffset.width > completeThreshold ? "松开完成" :
                            "左滑取消，右滑完成"
                        )
                        .foregroundColor(
                            dragOffset.width < cancelThreshold ? .red :
                            dragOffset.width > completeThreshold ? .green :
                            .primary
                        )
                        .animation(.easeOut, value: dragOffset)
                    }
                    
                    // 录音时长
                    if isRecording {
                        Text(String(format: "%.1f", audioManager.currentTime))
                            .font(.title)
                            .foregroundColor(.red)
                    }
                    
                    // 录音按钮
                    Circle()
                        .fill(isRecording ? Color.red : Color.blue)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "mic.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        )
                        .offset(x: dragOffset.width)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if isRecording {
                                        dragOffset = gesture.translation
                                    }
                                }
                                .onEnded { _ in
                                    handleRecordingEnd()
                                }
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.1)
                                .onEnded { _ in
                                    startRecording()
                                }
                        )
                        .animation(.spring(), value: dragOffset)
                }
                
                Spacer()
                
                // 右侧完成指示
                if isRecording {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(
                            dragOffset.width > 0 ? 
                            min(1.0, dragOffset.width / completeThreshold) : 0.3
                        ))
                        .frame(width: 44)
                        .animation(.easeOut, value: dragOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)
        }
    }
    
    private func startRecording() {
        recordingURL = audioManager.startRecording()
        isRecording = true
        recordingStartTime = Date()
    }
    
    private func handleRecordingEnd() {
        defer {
            isRecording = false
            dragOffset = .zero
            recordingStartTime = nil
        }
        
        guard let url = recordingURL else { return }
        
        let duration = audioManager.stopRecording()
        
        // 根据拖动距离定完成还是取消
        if dragOffset.width < cancelThreshold {
            // 左滑取消录音
            try? FileManager.default.removeItem(at: url)
        } else if dragOffset.width > completeThreshold || duration >= 1.0 {
            // 右滑完成录音（或录音时长超过1秒）
            let recording = Recording(
                practiceItemId: item.id ?? 0,
                date: recordingStartTime ?? Date(),
                duration: duration,
                fileURL: url
            )
            dbManager.saveRecording(recording)
            handleRecordingFinished(recording)
        } else {
            // 滑动距离不够，视为取消
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func handleRecordingFinished(_ recording: Recording) {
        Task {
            do {
                let transcribedText = try await speechRecognizer.transcribeAudio(url: recording.fileURL)
                let scoreManager = ScoreManager()
                let (similarity, mismatches) = scoreManager.calculateScore(
                    original: item.content,
                    transcribed: transcribedText
                )
                
                let score = SpeechScore(
                    recordingId: recording.id,
                    transcribedText: transcribedText,
                    matchScore: similarity,
                    mismatchedWords: mismatches
                )
                
                await MainActor.run {
                    dbManager.saveScore(score)
                }
            } catch {
                print("Speech recognition error: \(error)")
            }
        }
    }
}

// 添加 RecordingRow
struct RecordingRow: View {
    let recording: Recording
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var showScoreSheet = false
    @State private var score: SpeechScore?
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: recording.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    if audioManager.isPlaying && audioManager.currentRecordingURL == recording.fileURL {
                        audioManager.stopPlaying()
                    } else {
                        audioManager.playRecording(url: recording.fileURL)
                    }
                }) {
                    Image(systemName: audioManager.isPlaying && audioManager.currentRecordingURL == recording.fileURL ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading) {
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1f秒", recording.duration))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if let score = score {
                    Button(action: { showScoreSheet = true }) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("\(Int(score.matchScore * 100))分")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(scoreColor(score.matchScore))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            score = dbManager.loadScore(for: recording.id)
        }
        .sheet(isPresented: $showScoreSheet) {
            if let score = score {
                NavigationView {
                    ScoreView(score: score, originalText: recording.practiceItem?.content ?? "")
                        .navigationTitle("口语评分详情")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("关闭") {
                                    showScoreSheet = false
                                }
                            }
                        }
                }
            }
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.8...: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
}

struct ScoreView: View {
    let score: SpeechScore
    let originalText: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 评分部分
                HStack {
                    Text("口语评分")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(score.matchScore * 100))分")
                        .font(.title)
                        .foregroundColor(scoreColor)
                }
                
                Divider()
                
                // 文本对比部分
                let diffs = findDifferences(
                    original: originalText,
                    recognized: score.transcribedText
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("原文:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextComparisonView(
                        text: originalText,
                        differences: diffs.original,
                        isOriginal: true
                    )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("识别文本:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextComparisonView(
                        text: score.transcribedText,
                        differences: diffs.recognized,
                        isOriginal: false
                    )
                }
                
                Divider()
                
                // 统计信息
                VStack(alignment: .leading, spacing: 8) {
                    Text("统计信息:")
                        .font(.headline)
                    
                    let stats = calculateStats()
                    Group {
                        StatRow(title: "原文字数", value: "\(stats.originalCount)")
                        StatRow(title: "识别字数", value: "\(stats.recognizedCount)")
                        StatRow(title: "正确字数", value: "\(stats.correctCount)")
                        StatRow(title: "错误字数", value: "\(stats.errorCount)", isError: true)
                        StatRow(title: "准确率", value: "\(String(format: "%.1f%%", stats.accuracy * 100))")
                    }
                }
            }
            .padding()
        }
    }
    
    private var scoreColor: Color {
        switch score.matchScore {
        case 0.8...: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
    
    private struct Stats {
        let originalCount: Int
        let recognizedCount: Int
        let correctCount: Int
        let errorCount: Int
        let accuracy: Double
    }
    
    private func calculateStats() -> Stats {
        // 过滤掉标点符号和空白字符
        let originalChars = originalText.filter { !$0.isPunctuation && !$0.isWhitespace }
        let recognizedChars = score.transcribedText.filter { !$0.isPunctuation && !$0.isWhitespace }
        
        let originalCount = originalChars.count
        let recognizedCount = recognizedChars.count
        
        // 使用 findDifferences 函数来计算正确和错误的字符数
        let differences = findDifferences(original: originalChars, recognized: recognizedChars)
        let correctCount = differences.original.filter { $0.isMatch }.count
        let errorCount = originalCount - correctCount  // 错误字数为原文总数减去正确字数
        
        return Stats(
            originalCount: originalCount,
            recognizedCount: recognizedCount,
            correctCount: correctCount,
            errorCount: errorCount,
            accuracy: Double(correctCount) / Double(originalCount)
        )
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var isError: Bool = false
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(isError ? .red : .primary)
        }
        .font(.subheadline)
    }
}

struct TextComparisonView: View {
    let text: String
    let differences: [TextDifference]
    let isOriginal: Bool
    
    var body: some View {
        let attributedText = createAttributedText()
        Text(attributedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
    
    private func createAttributedText() -> AttributedString {
        var attributed = AttributedString(text)
        
        // 应用差异标记
        for diff in differences {
            if !diff.isMatch {
                let startIndex = text.index(text.startIndex, offsetBy: diff.startIndex)
                let endIndex = text.index(text.startIndex, offsetBy: diff.endIndex)
                let range = startIndex..<endIndex
                
                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].foregroundColor = .red
                    attributed[attributedRange].backgroundColor = .red.opacity(0.1)
                    
                    if !isOriginal {
                        attributed[attributedRange].setAttributes(AttributeContainer([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: UIColor.red
                        ]))
                    }
                }
            }
        }
        
        return attributed
    }
}