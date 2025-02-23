import SwiftUI

//struct ContentView: View {
//    var body: some View {
//        NavigationView {
//            TopicListView()
//        }
//    }
//}

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
        
        // 添加小延迟以确保加载动画流畅
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

// 修改 PracticeRoomView
struct PracticeRoomView: View {
    let item: PracticeItem
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var selectedTab = 0
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 0) {
            // 自定义顶部标签栏
            HStack(spacing: 0) {
                TabButton(
                    title: "文章",
                    systemImage: "doc.text",
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }
                
                TabButton(
                    title: "练习记录",
                    systemImage: "waveform",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
                .padding(.top, 8)
            
            // 内容区域
            TabView(selection: $selectedTab) {
                ArticleView(item: item)
                    .tag(0)
                
                RecordingsView(recordings: dbManager.recordings)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let id = item.id {
                dbManager.loadRecordings(for: id)
            }
        }
        .interactiveDismissDisabled()
    }
}

// 添加自定义标签按钮
struct TabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16))
                    Text(title)
                        .font(.headline)
                }
                .foregroundColor(isSelected ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // 底部指示条
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
    }
}


//
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
                    .foregroundColor(practiceCount == 0 ? .red : .primary)
                    .lineLimit(1)  // 限制为单行
                    .truncationMode(.tail)  // 使用省略号
                
                Spacer(minLength: 8)  // 最小间距
                
                if practiceCount == 0 {
                    Text("NEW")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                } else {
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
                        .foregroundColor(.red)
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
    @StateObject private var ttsManager = TTSManager.shared
    
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
                    if !item.mp3Url.isEmpty {
                        // 处理变量替换
                        let playUrl = item.mp3Url.replacingOccurrences(
                            of: ".content",
                            with: item.content.addingPercentEncoding(
                                withAllowedCharacters: .urlQueryAllowed
                            ) ?? ""
                        )
                        audioManager.playStreamingAudio(url: playUrl)
                    } else {
                        audioManager.playContent(item.content)
                    }
                }
            }) {
                HStack {
                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                    Text(audioManager.isPlaying ? "暂停" : "播放")
                    if item.mp3Url.isEmpty {
                        Text("(系统朗读)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.blue)
                .padding()
            }
            
            // 如果是系统朗读，添加语速控制
            if item.mp3Url.isEmpty {
                HStack {
                    Text("语速")
                    Slider(
                        value: Binding(
                            get: { Double(ttsManager.speechRate) },
                            set: { ttsManager.speechRate = Float($0) }
                        ),
                        in: 0.1...0.75
                    )
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            RecordButton(item: item)
                .frame(height: 100)
                .padding(.bottom)
        }
    }
}

// 修改 RecordingsView
struct RecordingsView: View {
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var dbManager = DatabaseManager.shared
    let recordings: [Recording]
    
    var body: some View {
        List {
            ForEach(recordings) { recording in
                RecordingRow(recording: recording)
                    .contextMenu {  // 使用长按菜单替代滑动删除
                        Button(role: .destructive) {
                            // 删除录音文件
                            let fileURL = recording.fileURL
                            try? FileManager.default.removeItem(at: fileURL)
                            
                            // 删除数据库记录
                            dbManager.deleteRecording(recording)
                            
                            // 重新加载录音列表
                            dbManager.loadRecordings(for: recording.practiceItemId)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
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



