import SwiftUI

@main
struct SpeakEasyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @AppStorage("hasGeneratedHistory") private var hasGeneratedHistory = true
    
    var body: some View {
        TabView {
            DailyPracticeView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("每日一练")
                }
            
            NavigationView {
                TopicListView()
            }
            .tabItem {
                Image(systemName: "books.vertical")
                Text("练习专题")
            }
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person")
                    Text("我的")
                }
        }
        .onAppear {
            // 检查并生成每日练习题目
            if dbManager.loadTodayPracticeItem() == nil {
                _ = dbManager.generateDailyPracticeItem()
            }
                        
//            dbManager.generateHistoryPractices()
            // 只在首次启动时生成历史记录
//            if !hasGeneratedHistory {
//                dbManager.generateHistoryPractices()
//                hasGeneratedHistory = true
//            }
        }
    }
}
