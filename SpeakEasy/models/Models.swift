import Foundation

struct PracticeItem: Identifiable, Codable {
    var id: Int?
    let title: String
    let content: String
    var isRead: Bool?
    var difficulty: Int?
    var category: String?
    var mp3Url: String
    var topicId: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case isRead
        case difficulty
        case category
        case mp3Url = "mp3_url"
        case topicId = "topic_id"
    }
    
    init(id: Int? = nil, 
         title: String, 
         content: String, 
         isRead: Bool? = false,
         difficulty: Int? = 1,
         category: String? = "General",
         mp3Url: String = "",
         topicId: Int) {
        self.id = id
        self.title = title
        self.content = content
        self.isRead = isRead
        self.difficulty = difficulty
        self.category = category
        self.mp3Url = mp3Url
        self.topicId = topicId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Custom"
        mp3Url = try container.decodeIfPresent(String.self, forKey: .mp3Url) ?? ""
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId) ?? 1
    }
}

struct Recording: Identifiable, Codable {
    let id: UUID
    let practiceItemId: Int
    let date: Date
    let duration: TimeInterval
    let fileURL: URL
    var note: String?
    var practiceItem: PracticeItem?
    
    init(id: UUID = UUID(), 
         practiceItemId: Int, 
         date: Date = Date(), 
         duration: TimeInterval = 0,
         fileURL: URL,
         note: String? = nil,
         practiceItem: PracticeItem? = nil) {
        self.id = id
        self.practiceItemId = practiceItemId
        self.date = date
        self.duration = duration
        self.fileURL = fileURL
        self.note = note
        self.practiceItem = practiceItem
    }
}

enum AppError: Error {
    case databaseError(String)
    case audioError(String)
    case fileError(String)
}

struct SpeechScore: Codable {
    let recordingId: UUID
    let transcribedText: String
    let matchScore: Double
    let mismatchedWords: [MismatchedWord]
}

struct MismatchedWord: Codable {
    let word: String
    let startIndex: Int
    let endIndex: Int
}

struct Topic: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String
    let createdAt: Date
    let isPreset: Bool
    var practiceCount: Int = 0
    
    init(id: Int = 0,
         name: String,
         description: String = "",
         createdAt: Date = Date(),
         isPreset: Bool = false,
         practiceCount: Int = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.isPreset = isPreset
        self.practiceCount = practiceCount
    }
}

struct DailyPractices: Identifiable {
    let id: String  // 日期字符串，格式：yyyy-MM-dd
    let date: Date
    let items: [PracticeItem]
} 