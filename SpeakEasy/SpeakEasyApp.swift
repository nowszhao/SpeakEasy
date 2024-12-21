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

// 每日一练视图
struct DailyPracticeView: View {
    @StateObject private var dbManager = DatabaseManager.shared
    @State private var dailyItem: PracticeItem?
    @State private var practiceHistory: [DailyPractices] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 只在未完成今日练习时显示 dailyItem
                    if let item = dailyItem,
                       !hasCompletedToday(item) {
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
                        // 如果是今天的记录，并且已经显示了 dailyItem，就跳过
                        if Calendar.current.isDateInToday(daily.date) && 
                           dailyItem != nil && !hasCompletedToday(dailyItem!) {
                            EmptyView()
                        } else {
                            TimelineSection(
                                date: daily.date,
                                title: formatDate(daily.date),
                                isFirst: (dailyItem == nil || hasCompletedToday(dailyItem!)) && index == 0,
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
                }
                .padding(.top)
            }
            .navigationTitle("每日一练")
            .onAppear {
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
        print("\n📅 加载每日练习...")
        if let todayItem = dbManager.loadTodayPracticeItem() {
            print("✅ 加载到今日练习: ID=\(todayItem.id ?? -1), 标题=\(todayItem.title)")
            dailyItem = todayItem
        } else {
            print("🆕 生成新的每日练习")
            dailyItem = dbManager.generateDailyPracticeItem()
        }
    }
    
    private func loadPracticeHistory() {
        print("\n📚 加载练习历史...")
        practiceHistory = dbManager.loadPracticeHistory()
        print("📊 加载到 \(practiceHistory.count) 天的练习记录")
        
        // 打印每天的练习详情
        for daily in practiceHistory {
//            print("📅 \(formatDate(daily.date)): \(daily.items.count) 个练习")
            for item in daily.items {
                print("  - ID=\(item.id ?? -1), 标题=\(item.title)")
            }
        }
    }
    
    // 添加检查今日练习是否已完成的方法
    private func hasCompletedToday(_ item: PracticeItem) -> Bool {
        let todayPractices = practiceHistory.first { 
            Calendar.current.isDateInToday($0.date)
        }
        return todayPractices?.items.contains(where: { $0.id == item.id }) ?? false
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
        HStack(alignment: .top, spacing: 15) {
            // 时间轴部分
            VStack(spacing: 0) {
                // 为了和文字对齐，添加一个顶部间距
                Color.clear.frame(height: 4)  // 微调此值以实现完美对齐
                
                ZStack(alignment: .center) {
                    // 背景连接线
                    if !isFirst {
                        Rectangle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 2)
                            .offset(y: -10)
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

// 添加 Date 扩展
extension Date {
    func isInSameDay(as date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(self, inSameDayAs: date)
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

