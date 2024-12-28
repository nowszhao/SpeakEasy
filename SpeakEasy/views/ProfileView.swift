import SwiftUI

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


// 修改 ContributionGraph 视图
struct ContributionGraph: View {
    let contributions: [[PracticeContribution?]]
    let months: [String]
    
    // 添加 ScrollView 的引用
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var hasScrolledToToday = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 月份标签
            HStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    Text(month)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 28)
            
            HStack(alignment: .top, spacing: 12) {
                // 星期标签
                VStack(alignment: .leading, spacing: 20) { // 增加间距使其对齐方块中心
                    Text("Mon").font(.caption2)
                    Text("Wed").font(.caption2)
                    Text("Fri").font(.caption2)
                }
                .foregroundColor(.secondary)
                .frame(width: 28)
                .offset(y: 6) // 微调垂直位置以对齐方块中心
                
                // 贡献方块
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(contributions.enumerated()), id: \.offset) { weekIndex, week in
                                VStack(spacing: 4) {
                                    ForEach(0..<7, id: \.self) { day in
                                        if let contribution = week[day] {
                                            ContributionCell(intensity: contribution.intensity)
                                                .id("\(weekIndex)-\(contribution.id)") // 添加唯一标识
                                        } else {
                                            ContributionCell(intensity: 0)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 12) // 添加尾部间距以确保最后一列完全显示
                    }
                    .onAppear {
                        scrollViewProxy = proxy
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollToToday()
                        }
                    }
                }
            }
            
            // 图例
            HStack(alignment: .center, spacing: 8) {
                Text("Strength:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize() // 防止文本换行
                    
                    HStack(spacing: 4) {
                        ForEach(0...4, id: \.self) { intensity in
                            ContributionCell(intensity: intensity)
                                .frame(width: 12, height: 12)
                        }
                    }
                    
                    Text("More")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize() // 防止文本换行
                }
                
                Spacer()
            }
            .padding(.leading, 28)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
    
    // 修改 scrollToToday 方法
    private func scrollToToday() {
        guard !hasScrolledToToday else { return }
        
        // 查找今天的贡献格子
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        
        // 查找包含今天的周
        for (weekIndex, week) in contributions.enumerated() {
            if let todayContribution = week.compactMap({ $0 }).first(where: { $0.id == todayString }) {
                // 滚动到对应位置
                withAnimation {
                    scrollViewProxy?.scrollTo("\(weekIndex)-\(todayString)", anchor: .trailing)
                }
                hasScrolledToToday = true
                break
            }
        }
    }
}

// 贡献方块单元格
struct ContributionCell: View {
    let intensity: Int
    
    private var color: Color {
        switch intensity {
        case 0: return Color(.systemGray6)
        case 1: return Color.green.opacity(0.2)
        case 2: return Color.green.opacity(0.4)
        case 3: return Color.green.opacity(0.6)
        case 4: return Color.green.opacity(0.8)
        default: return Color(.systemGray6)
        }
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 16, height: 16)
    }
}

// 练习记录数据结构
struct PracticeContribution: Identifiable {
    let id: String // 日期字符串 yyyy-MM-dd
    let date: Date
    let score: Int // 最高分
    let count: Int // 练习次数
    
    var intensity: Int {
        if count == 0 { return 0 }
        if score < 60 { return 1 }
        if score < 75 { return 2 }
        if score < 85 { return 3 }
        return 4
    }
}
