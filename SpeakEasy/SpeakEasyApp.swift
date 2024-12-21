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
        }
    }
}

// 每日一练视图
struct DailyPracticeView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var dailyItem: PracticeItem?
    @State private var practiceHistory: [DailyPractices] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let item = dailyItem {
                        TimelineSection(
                            date: Date(),
                            title: "今天",
                            isFirst: true,
                            isLast: practiceHistory.isEmpty
                        ) {
                            NavigationLink {
                                PracticeRoomView(item: item)
                            } label: {
                                PracticeItemRow(item: item)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    ForEach(Array(practiceHistory.enumerated()), id: \.element.id) { index, daily in
                        TimelineSection(
                            date: daily.date,
                            title: formatDate(daily.date),
                            isFirst: dailyItem == nil && index == 0,
                            isLast: index == practiceHistory.count - 1
                        ) {
                            ForEach(daily.items) { item in
                                NavigationLink {
                                    PracticeRoomView(item: item)
                                } label: {
                                    PracticeItemRow(item: item)
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle("每日一练")
            .onAppear {
//                dbManager.generateHistoryPractices()
                loadDailyPractice()
                loadPracticeHistory()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "今天"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M月d日"
            if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
                dateFormatter.dateFormat = "yyyy年M月d日"
            }
            return dateFormatter.string(from: date)
        }
    }
    
    private func loadDailyPractice() {
        if let todayItem = dbManager.loadTodayPracticeItem() {
            dailyItem = todayItem
        } else {
            dailyItem = dbManager.generateDailyPracticeItem()
        }
    }
    
    private func loadPracticeHistory() {
        practiceHistory = dbManager.loadPracticeHistory()
    }
}

// 添加时间轴节点视图
struct TimelineSection<Content: View>: View {
    let date: Date
    let title: String
    let isFirst: Bool
    let isLast: Bool
    let content: () -> Content
    
    init(
        date: Date,
        title: String,
        isFirst: Bool = false,
        isLast: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.date = date
        self.title = title
        self.isFirst = isFirst
        self.isLast = isLast
        self.content = content
    }
    
    var body: some View {
        HStack(spacing: 15) {
            // 时间轴部分
            ZStack(alignment: .center) {
                // 背景连接线
                if !isFirst {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 2)
                        .offset(y: -10) // 向上延伸以确保连接
                }
                
                VStack(spacing: 0) {
                    // 时间点
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                    
                    // 下半部分连接线
                    if !isLast {
                        Rectangle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: 26)
            
            // 右侧内容
            VStack(alignment: .leading, spacing: 8) {
                // 日期标题
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // 内容区域
                content()
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
}


// 修改 ProfileView 部分
struct ProfileView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var contributions: [[PracticeContribution?]] = []
    @State private var months: [String] = []
    
    // 添加版本信息
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        NavigationView {
            List {
                // 用户信息部分
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("慢慢说")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("坚持练习，提升表达")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // 练习统计部分
                Section {
                    ContributionGraph(contributions: contributions, months: months)
                        .listRowInsets(EdgeInsets())
                }
                
                // 版本信息部分
                Section {
                    HStack {
                        Text("版本")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("我的")
            .onAppear {
                loadContributions()
            }
        }
    }
    
    private func loadContributions() {
        contributions = dbManager.loadContributions()
        months = dbManager.getContributionMonths(weeks: contributions)
    }
}
