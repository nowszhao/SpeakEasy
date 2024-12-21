import SwiftUI
import UIKit
import UniformTypeIdentifiers

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