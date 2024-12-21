import SwiftUI

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