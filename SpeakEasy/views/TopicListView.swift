import SwiftUI

struct TopicListView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var showImportSheet = false
    @State private var showingImportDialog = false
    @State private var newTopicName = ""
    @State private var newTopicDescription = ""
    @State private var selectedFileURL: URL?
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            ForEach(dbManager.topics) { topic in
                NavigationLink {
                    PracticeListView(topicId: topic.id)
                } label: {
                    TopicRow(topic: topic)
                }
            }
            .onDelete { indexSet in
                deleteTopic(at: indexSet)
            }
        }
        .navigationTitle("练习专题")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showImportSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportTopicView(
                isPresented: $showImportSheet,
                topicName: $newTopicName,
                description: $newTopicDescription,
                onImport: { url in
                    selectedFileURL = url
                    showingImportDialog = true
                }
            )
        }
        .alert("导入专题", isPresented: $showingImportDialog) {
            TextField("专题名称", text: $newTopicName)
            TextField("专题描述", text: $newTopicDescription)
            Button("取消", role: .cancel) { }
            Button("导入") {
                if let url = selectedFileURL {
                    importTopic(from: url)
                }
            }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            dbManager.loadTopics()
        }
    }
    
    private func importTopic(from url: URL) {
        Task {
            do {
                if newTopicName.isEmpty {
                    alertMessage = "请输入专题名称"
                    showAlert = true
                    return
                }
                
                try await dbManager.importCustomJSON(
                    from: url,
                    topicName: newTopicName,
                    description: newTopicDescription
                )
                
                // 清理状态
                newTopicName = ""
                newTopicDescription = ""
                selectedFileURL = nil
                
                alertMessage = "导入成功"
                showAlert = true
            } catch {
                print("导入失败：\(error)")
                alertMessage = "导入失败：\(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func deleteTopic(at indexSet: IndexSet) {
        for index in indexSet {
            let topic = dbManager.topics[index]
            if topic.isPreset {
                alertMessage = "预设专题不能删除"
                showAlert = true
                return
            }
            
            Task {
                do {
                    try await dbManager.deleteTopic(topic)
                } catch {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

struct TopicRow: View {
    let topic: Topic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(topic.name)
                    .font(.headline)
                if topic.isPreset {
                    Text("预设")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            
            if !topic.description.isEmpty {
                Text(topic.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "doc.text")
                Text("\(topic.practiceCount) 个练习")
                
                Spacer()
                
                Text(topic.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
