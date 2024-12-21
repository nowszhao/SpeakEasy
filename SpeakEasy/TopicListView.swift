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