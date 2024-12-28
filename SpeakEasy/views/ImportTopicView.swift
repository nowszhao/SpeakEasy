import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct ImportTopicView: View {
    @Binding var isPresented: Bool
    @Binding var topicName: String
    @Binding var description: String
    var onImport: (URL) -> Void
    
    @State private var showFilePicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("专题信息")) {
                    TextField("专题名称", text: $topicName)
                    TextField("专题描述（可选）", text: $description)
                }
                
                Section {
                    Button(action: {
                        showFilePicker = true
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("选择JSON文件")
                        }
                    }
                }
                
                Section {
                    DisclosureGroup("JSON模板说明") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("文件格式示例:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("""
                            [
                                {
                                    "title": "xxx",
                                    "content": "xxxx",
                                    "mp3_url": null
                                },
                                ...
                            ]
                            """)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("导入专题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                FilePicker(onFilePicked: { url in
                    if topicName.isEmpty {
                        alertMessage = "请输入专题名称"
                        showAlert = true
                    } else {
                        onImport(url)
                        isPresented = false
                    }
                }, onCancel: {
                    showFilePicker = false
                })
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
}

#Preview {
    ImportTopicView(
        isPresented: .constant(true),
        topicName: .constant(""),
        description: .constant(""),
        onImport: { _ in }
    )
} 


struct FilePicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: FilePicker

        init(parent: FilePicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else { return }
            
            // 获取安全访问权限
            guard selectedURL.startAccessingSecurityScopedResource() else {
                print("❌ 无法获取文件访问权限")
                return
            }
            
            defer {
                selectedURL.stopAccessingSecurityScopedResource()
            }
            
            // 创建临时目录URL
            let tempDirectoryURL = FileManager.default.temporaryDirectory
            let tempFileURL = tempDirectoryURL.appendingPathComponent(selectedURL.lastPathComponent)
            
            do {
                // 如果临时文件已存在，先删除
                if FileManager.default.fileExists(atPath: tempFileURL.path) {
                    try FileManager.default.removeItem(at: tempFileURL)
                }
                
                // 读取原文件数据
                let data = try Data(contentsOf: selectedURL)
                
                // 写入临时文件
                try data.write(to: tempFileURL)
                
                print("✅ 成功复制文件到临时目录: \(tempFileURL.path)")
                
                // 调用回调
                parent.onFilePicked(tempFileURL)
            } catch {
                print("❌ 文件处理错误：\(error)")
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }

    var onFilePicked: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let jsonType = UTType.json
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [jsonType])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
