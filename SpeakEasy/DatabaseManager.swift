import Foundation
import SQLite3

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    
    @Published var practiceItems: [PracticeItem] = []
    @Published var recordings: [Recording] = []
    @Published var topics: [Topic] = []
    @Published var currentTopicId: Int = 1  // 当前选中的专题
    
    private init() {
        deleteOldDatabase()
        openDatabase()
        createTables()
        loadInitialData()
    }
    
    private func deleteOldDatabase() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("practice.sqlite")
        try? FileManager.default.removeItem(at: fileURL)
        print("删除旧数据库文件: \(fileURL.path)")
    }
    
    private func openDatabase() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("practice.sqlite")
        print("Database path: \(fileURL.path)")
        
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error opening database")
            return
        }
    }
    
    private func createTables() {
        print("开始创建数据库表...")
        
        // 删除所有现有表（按照外键依赖的反序删除）
        let dropTablesQuery = """
        DROP TABLE IF EXISTS speech_scores;
        DROP TABLE IF EXISTS recordings;
        DROP TABLE IF EXISTS practice_items;
        DROP TABLE IF EXISTS topics;
        """
        
        executeQuery(dropTablesQuery)
        print("已删除旧表")
        
        // 按照依赖顺序创建表
        let createTopicsTableQuery = """
        CREATE TABLE IF NOT EXISTS topics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            is_preset INTEGER DEFAULT 0
        );
        """
        
        let createPracticeItemsTableQuery = """
        CREATE TABLE IF NOT EXISTS practice_items (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            is_read INTEGER DEFAULT 0,
            difficulty INTEGER DEFAULT 1,
            category TEXT DEFAULT 'General',
            mp3_url TEXT,
            topic_id INTEGER NOT NULL,
            last_read_date TEXT DEFAULT NULL,
            FOREIGN KEY(topic_id) REFERENCES topics(id)
        );
        """
        
        let createRecordingsTableQuery = """
        CREATE TABLE IF NOT EXISTS recordings (
            id TEXT PRIMARY KEY,
            practice_item_id INTEGER,
            date TEXT NOT NULL,
            duration REAL DEFAULT 0,
            file_url TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(practice_item_id) REFERENCES practice_items(id)
        );
        """
        
        let createScoresTableQuery = """
        CREATE TABLE IF NOT EXISTS speech_scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id TEXT NOT NULL,
            transcribed_text TEXT NOT NULL,
            match_score REAL NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(recording_id) REFERENCES recordings(id)
        );
        """
        
        // 按顺序创建表
        print("创建 topics 表...")
        executeQuery(createTopicsTableQuery)
        
        print("创建 practice_items 表...")
        executeQuery(createPracticeItemsTableQuery)
        
        print("创建 recordings 表...")
        executeQuery(createRecordingsTableQuery)
        
        print("创建 speech_scores 表...")
        executeQuery(createScoresTableQuery)
        
        // 修改创建默认专题的逻辑
        print("创建默认专题...")
        let defaultTopicQuery = """
        INSERT INTO topics (id, name, description, is_preset)
        SELECT 1, '得到60', '得到专栏60秒音频文章', 1
        WHERE NOT EXISTS (SELECT 1 FROM topics WHERE id = 1);
        """
        executeQuery(defaultTopicQuery)
        
        print("数据库表创建完成")
    }
    
    private func executeQuery(_ query: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("Error executing query: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("Error preparing query: \(errorMessage)")
        }
        sqlite3_finalize(statement)
    }
    
    func loadPracticeItems(filter: ItemFilter = .all) {
        let query: String
        switch filter {
        case .all:
            query = """
            SELECT p.*, COUNT(r.id) as recording_count
            FROM practice_items p
            LEFT JOIN recordings r ON p.id = r.practice_item_id
            WHERE p.topic_id = ?
            GROUP BY p.id
            ORDER BY p.id;
            """
        case .recent:
            query = """
            SELECT p.*, COUNT(r.id) as recording_count, MAX(r.date) as latest_recording
            FROM practice_items p
            INNER JOIN recordings r ON p.id = r.practice_item_id
            WHERE p.topic_id = ?
            GROUP BY p.id
            HAVING recording_count > 0
            ORDER BY latest_recording DESC
            LIMIT 10;
            """
        }
        
        var statement: OpaquePointer?
        var items: [PracticeItem] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(currentTopicId))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let content = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let recordingCount = Int(sqlite3_column_int(statement, 8))
                let isRead = recordingCount > 0
                
                let difficulty = Int(sqlite3_column_int(statement, 4))
                let category = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "General"
                let mp3Url = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
                
                let item = PracticeItem(
                    id: id,
                    title: title,
                    content: content,
                    isRead: isRead,
                    difficulty: difficulty,
                    category: category,
                    mp3Url: mp3Url,
                    topicId: Int(sqlite3_column_int(statement, 7))
                )
                items.append(item)
            }
        }
        sqlite3_finalize(statement)
        
        DispatchQueue.main.async {
            self.practiceItems = items
        }
    }
    
    private func loadInitialData() {
        guard let db = db else {
            print("Database connection not available")
            return
        }
        
        let query = "SELECT COUNT(*) FROM practice_items;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                if count == 0 {
                    importJSONData()
                }
            }
        }
        sqlite3_finalize(statement)
        
        loadPracticeItems()
    }
    
    private func importJSONData() {
        guard let db = db else {
            print("Database connection not available")
            return
        }
        
        guard let url = Bundle.main.url(forResource: "dedao60", withExtension: "json") else {
            print("Error: Cannot find dedao60.json in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([PracticeItem].self, from: data)
            
            for (index, var item) in items.enumerated() {
                item.id = index + 1
                
                let query = """
                INSERT INTO practice_items (id, title, content, is_read, difficulty, category, mp3_url, topic_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
                
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, Int32(item.id!))
                    sqlite3_bind_text(statement, 2, (item.title as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 3, (item.content as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 4, item.isRead ?? false ? 1 : 0)
                    sqlite3_bind_int(statement, 5, Int32(item.difficulty ?? 1))
                    sqlite3_bind_text(statement, 6, ((item.category ?? "General") as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 7, (item.mp3Url as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 8, 1)  // 默认专题ID为1
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        print("Error inserting item: \(item.title)")
                    }
                }
                sqlite3_finalize(statement)
            }
            print("JSON data imported successfully")
        } catch {
            print("Error importing JSON data: \(error)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func saveRecording(_ recording: Recording) {
        guard let db = db else { return }
        
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        let recordingQuery = """
        INSERT INTO recordings (id, practice_item_id, date, duration, file_url, note)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, recordingQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (recording.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(recording.practiceItemId))
            
            let dateFormatter = ISO8601DateFormatter()
            let dateString = dateFormatter.string(from: recording.date)
            sqlite3_bind_text(statement, 3, (dateString as NSString).utf8String, -1, nil)
            
            sqlite3_bind_double(statement, 4, recording.duration)
            sqlite3_bind_text(statement, 5, (recording.fileURL.path as NSString).utf8String, -1, nil)
            
            if let note = recording.note {
                sqlite3_bind_text(statement, 6, (note as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error saving recording")
            }
        }
        sqlite3_finalize(statement)
        
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        
        loadRecordings(for: recording.practiceItemId)
        loadPracticeItems()
    }
    
    func loadRecordings(for practiceItemId: Int) {
        let query = """
        SELECT r.id, r.date, r.duration, r.file_url, r.note,
               p.title, p.content, p.is_read, p.difficulty, p.category, p.mp3_url, p.topic_id
        FROM recordings r
        LEFT JOIN practice_items p ON r.practice_item_id = p.id
        WHERE r.practice_item_id = ?
        ORDER BY r.date DESC;
        """
        
        var statement: OpaquePointer?
        var loadedRecordings: [Recording] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(practiceItemId))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(statement, 0))
                let dateString = String(cString: sqlite3_column_text(statement, 1))
                let duration = sqlite3_column_double(statement, 2)
                let fileURLString = String(cString: sqlite3_column_text(statement, 3))
                
                let dateFormatter = ISO8601DateFormatter()
                let date = dateFormatter.date(from: dateString) ?? Date()
                let fileURL = URL(fileURLWithPath: fileURLString)
                
                var note: String?
                if let noteText = sqlite3_column_text(statement, 4) {
                    note = String(cString: noteText)
                }
                
                // 加载 PracticeItem 据
                let title = String(cString: sqlite3_column_text(statement, 5))
                let content = String(cString: sqlite3_column_text(statement, 6))
                let isRead = sqlite3_column_int(statement, 7) != 0
                let difficulty = Int(sqlite3_column_int(statement, 8))
                let category = String(cString: sqlite3_column_text(statement, 9))
                let mp3Url = String(cString: sqlite3_column_text(statement, 10))
                let topicId = Int(sqlite3_column_int(statement, 11))
                
                let practiceItem = PracticeItem(
                    id: practiceItemId,
                    title: title,
                    content: content,
                    isRead: isRead,
                    difficulty: difficulty,
                    category: category,
                    mp3Url: mp3Url,
                    topicId: topicId
                )
                
                let recording = Recording(
                    id: UUID(uuidString: idString) ?? UUID(),
                    practiceItemId: practiceItemId,
                    date: date,
                    duration: duration,
                    fileURL: fileURL,
                    note: note,
                    practiceItem: practiceItem
                )
                
                loadedRecordings.append(recording)
            }
        }
        sqlite3_finalize(statement)
        
        DispatchQueue.main.async {
            self.recordings = loadedRecordings
        }
    }
    
    func deleteRecording(_ recording: Recording) {
        print("🗑️ 开始删除录音: \(recording.id)")
        guard let db = db else {
            print("❌ 数据库连接不可用")
            return
        }
        
        // 开���事务
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        // 1. 删除文件
        do {
            try FileManager.default.removeItem(at: recording.fileURL)
            print("✅ 录音文件删除成功")
        } catch {
            print(" 删除录音文件失败: \(error)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        // 2. 删除数据库记录
        let query = "DELETE FROM recordings WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (recording.id.uuidString as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ 删除数据库记录失败")
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            } else {
                print("✅ 数据库记录删除成功")
                sqlite3_exec(db, "COMMIT", nil, nil, nil)
            }
        }
        sqlite3_finalize(statement)
        
        // 重新加载录音列表
        loadRecordings(for: recording.practiceItemId)
    }
    
    func createScoresTable() {
        let query = """
        CREATE TABLE IF NOT EXISTS speech_scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id TEXT NOT NULL,
            transcribed_text TEXT NOT NULL,
            match_score REAL NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(recording_id) REFERENCES recordings(id)
        );
        """
        executeQuery(query)
    }
    
    func saveScore(_ score: SpeechScore) {
        let query = """
        INSERT INTO speech_scores (recording_id, transcribed_text, match_score)
        VALUES (?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (score.recordingId.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (score.transcribedText as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 3, score.matchScore)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error saving score")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func loadScore(for recordingId: UUID) -> SpeechScore? {
        let query = """
        SELECT transcribed_text, match_score
        FROM speech_scores 
        WHERE recording_id = ?;
        """
        
        var statement: OpaquePointer?
        var score: SpeechScore?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (recordingId.uuidString as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let transcribedText = String(cString: sqlite3_column_text(statement, 0))
                let matchScore = sqlite3_column_double(statement, 1)
                
                score = SpeechScore(
                    recordingId: recordingId,
                    transcribedText: transcribedText,
                    matchScore: matchScore,
                    mismatchedWords: [] // 简化版本，暂不加载具体的匹配词
                )
            }
        }
        sqlite3_finalize(statement)
        return score
    }
    
    struct PracticeStats {
        let practiceCount: Int
        let highestScore: Int
    }
    
    func loadPracticeStats(for practiceItemId: Int) -> PracticeStats {
        let query = """
        SELECT COUNT(r.id) as practice_count,
               IFNULL(MAX(ROUND(s.match_score * 100)), 0) as highest_score
        FROM recordings r
        LEFT JOIN speech_scores s ON r.id = s.recording_id
        WHERE r.practice_item_id = ?
        GROUP BY r.practice_item_id;
        """
        
        var statement: OpaquePointer?
        var practiceCount = 0
        var highestScore = 0
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(practiceItemId))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                practiceCount = Int(sqlite3_column_int(statement, 0))
                highestScore = Int(sqlite3_column_int(statement, 1))
            }
        }
        sqlite3_finalize(statement)
        
        return PracticeStats(practiceCount: practiceCount, highestScore: highestScore)
    }
    
    func importCustomJSON(from url: URL, topicName: String, description: String = "") async throws {
        guard let db = db else {
            throw AppError.databaseError("数据库连接不可用")
        }
        
        // 开始事务
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        do {
            // 1. 创建新专题
            let topicId = try await createTopic(name: topicName, description: description)
            
            // 2. 读取和解析JSON
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([PracticeItem].self, from: data)
            
            // 3. 导入练习项目
            for (index, var item) in items.enumerated() {
                item.id = try await getMaxPracticeItemId() + index + 1
                try await insertPracticeItem(item, topicId: topicId)
            }
            
            // 提交事务
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            
            // 重新加载据
            loadTopics()
            if currentTopicId == topicId {
                loadPracticeItems()
            }
            
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
    
    private func createTopic(name: String, description: String) async throws -> Int {
        let query = """
        INSERT INTO topics (name, description)
        VALUES (?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (description as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw AppError.databaseError("创建专题失败")
            }
        }
        sqlite3_finalize(statement)
        
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    private func getMaxPracticeItemId() async throws -> Int {
        guard let db = db else {
            throw AppError.databaseError("Database connection not available")
        }
        
        let query = "SELECT MAX(id) FROM practice_items;"
        var statement: OpaquePointer?
        var maxId = 0
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                maxId = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        return maxId
    }
    
    // 加载所有专题
    func loadTopics() {
        let query = """
        SELECT 
            t.id,
            t.name,
            t.description,
            t.created_at,
            t.is_preset,
            COUNT(DISTINCT p.id) as practice_count
        FROM topics t
        LEFT JOIN practice_items p ON t.id = p.topic_id
        GROUP BY t.id, t.name, t.description, t.created_at, t.is_preset
        ORDER BY t.created_at DESC;
        """
        
        var statement: OpaquePointer?
        var loadedTopics: [Topic] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let description = String(cString: sqlite3_column_text(statement, 2))
                let dateString = String(cString: sqlite3_column_text(statement, 3))
                let isPreset = sqlite3_column_int(statement, 4) != 0
                let practiceCount = Int(sqlite3_column_int(statement, 5))
                
                let dateFormatter = ISO8601DateFormatter()
                let createdAt = dateFormatter.date(from: dateString) ?? Date()
                
                let topic = Topic(
                    id: id,
                    name: name,
                    description: description,
                    createdAt: createdAt,
                    isPreset: isPreset,
                    practiceCount: practiceCount
                )
                loadedTopics.append(topic)
            }
        }
        sqlite3_finalize(statement)
        
        DispatchQueue.main.async {
            self.topics = loadedTopics
        }
    }
    
    // 添加插入练习项目的方法
    private func insertPracticeItem(_ item: PracticeItem, topicId: Int) throws {
        let query = """
        INSERT INTO practice_items (id, title, content, is_read, difficulty, category, mp3_url, topic_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(item.id!))
            sqlite3_bind_text(statement, 2, (item.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (item.content as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 4, item.isRead ?? false ? 1 : 0)
            sqlite3_bind_int(statement, 5, Int32(item.difficulty ?? 1))
            sqlite3_bind_text(statement, 6, ((item.category ?? "General") as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (item.mp3Url as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 8, Int32(topicId))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                throw AppError.databaseError("插入记录失败: \(error)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func deleteTopic(_ topic: Topic) throws {
        guard !topic.isPreset else {
            throw AppError.databaseError("预设专题不能删除")
        }
        
        guard let db = db else {
            throw AppError.databaseError("据库连接不可用")
        }
        
        // 开始事务
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        do {
            // 1. 删除评分记录
            let deleteScoresQuery = """
            DELETE FROM speech_scores
            WHERE recording_id IN (
                SELECT r.id
                FROM recordings r
                INNER JOIN practice_items p ON r.practice_item_id = p.id
                WHERE p.topic_id = ?
            );
            """
            try executeParameterizedQuery(deleteScoresQuery, parameters: [topic.id])
            
            // 2. 删除录音文件和记录
            let recordingsQuery = """
            SELECT file_url FROM recordings
            WHERE practice_item_id IN (
                SELECT id FROM practice_items WHERE topic_id = ?
            );
            """
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, recordingsQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(topic.id))
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let urlString = sqlite3_column_text(statement, 0) {
                        let fileURL = URL(fileURLWithPath: String(cString: urlString))
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }
            sqlite3_finalize(statement)
            
            // 删除录音记录
            let deleteRecordingsQuery = """
            DELETE FROM recordings
            WHERE practice_item_id IN (
                SELECT id FROM practice_items WHERE topic_id = ?
            );
            """
            try executeParameterizedQuery(deleteRecordingsQuery, parameters: [topic.id])
            
            // 3. 删除练习项目
            let deletePracticeItemsQuery = "DELETE FROM practice_items WHERE topic_id = ?;"
            try executeParameterizedQuery(deletePracticeItemsQuery, parameters: [topic.id])
            
            // 4. 删除专题
            let deleteTopicQuery = "DELETE FROM topics WHERE id = ?;"
            try executeParameterizedQuery(deleteTopicQuery, parameters: [topic.id])
            
            // 提交事务
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            
            // 重新加载数据
            loadTopics()
            
        } catch {
            // 回滚事务
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
    
    private func executeParameterizedQuery(_ query: String, parameters: [Any]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw AppError.databaseError("准备查询失败")
        }
        
        // 绑定参数
        for (index, parameter) in parameters.enumerated() {
            let parameterIndex = Int32(index + 1)
            switch parameter {
            case let value as Int:
                sqlite3_bind_int(statement, parameterIndex, Int32(value))
            case let value as String:
                sqlite3_bind_text(statement, parameterIndex, (value as NSString).utf8String, -1, nil)
            case let value as Double:
                sqlite3_bind_double(statement, parameterIndex, value)
            default:
                throw AppError.databaseError("不支持的参数类型")
            }
        }
        
        // 执行查询
        if sqlite3_step(statement) != SQLITE_DONE {
            throw AppError.databaseError("执行查询失败")
        }
        
        sqlite3_finalize(statement)
    }
    
    func loadTodayPracticeItem() -> PracticeItem? {
        let query = """
        SELECT p.*, COUNT(r.id) as recording_count
        FROM practice_items p
        LEFT JOIN recordings r ON p.id = r.practice_item_id
        WHERE DATE(r.date) = DATE('now', 'localtime')
        GROUP BY p.id
        ORDER BY r.date DESC
        LIMIT 1;
        """
        
        var statement: OpaquePointer?
        var item: PracticeItem?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW,
               let stmt = statement {  // 解包 statement
                item = extractPracticeItem(from: stmt)
            }
        }
        sqlite3_finalize(statement)
        
        return item
    }
    
    func generateDailyPracticeItem() -> PracticeItem? {
        let query = """
        SELECT p.*, COUNT(r.id) as recording_count
        FROM practice_items p
        LEFT JOIN recordings r ON p.id = r.practice_item_id
        WHERE p.id NOT IN (
            SELECT practice_item_id
            FROM recordings
            WHERE DATE(date) = DATE('now', 'localtime')
        )
        GROUP BY p.id
        ORDER BY RANDOM()
        LIMIT 1;
        """
        
        var statement: OpaquePointer?
        var item: PracticeItem?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW,
               let stmt = statement {  // 解包 statement
                item = extractPracticeItem(from: stmt)
            }
        }
        sqlite3_finalize(statement)
        
        return item
    }
    
    func loadPracticeHistory() -> [DailyPractices] {
        let query = """
        SELECT DISTINCT p.*, 
               COUNT(r.id) as recording_count, 
               MAX(r.date) as latest_date,
               DATE(r.date) as practice_date
        FROM practice_items p
        INNER JOIN recordings r ON p.id = r.practice_item_id
        GROUP BY p.id, DATE(r.date)
        ORDER BY practice_date DESC, latest_date DESC;
        """
        
        var statement: OpaquePointer?
        var practicesByDate: [String: (Date, [PracticeItem])] = [:]
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW,
                  let stmt = statement {
                if let item = extractPracticeItem(from: stmt),
                   let dateText = sqlite3_column_text(stmt, 11) {
                    let dateString = String(cString: dateText)
                    
                    // 转换日期
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let date = dateFormatter.date(from: dateString) ?? Date()
                    
                    // 按日期分组
                    if var existing = practicesByDate[dateString] {
                        existing.1.append(item)
                        practicesByDate[dateString] = existing
                    } else {
                        practicesByDate[dateString] = (date, [item])
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        
        // 转换为数组并排序
        return practicesByDate.map { dateString, value in
            DailyPractices(id: dateString, date: value.0, items: value.1)
        }.sorted { $0.date > $1.date }
    }
    
    private func extractPracticeItem(from statement: OpaquePointer) -> PracticeItem? {
        let id = Int(sqlite3_column_int(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let content = String(cString: sqlite3_column_text(statement, 2))
        let isRead = sqlite3_column_int(statement, 3) != 0
        let difficulty = Int(sqlite3_column_int(statement, 4))
        let category = String(cString: sqlite3_column_text(statement, 5))
        let mp3Url = String(cString: sqlite3_column_text(statement, 6))
        let topicId = Int(sqlite3_column_int(statement, 7))
        
        return PracticeItem(
            id: id,
            title: title,
            content: content,
            isRead: isRead,
            difficulty: difficulty,
            category: category,
            mp3Url: mp3Url,
            topicId: topicId
        )
    }
    
    func generateHistoryPractices() {
        // 检查是否已经有历史记录
        let checkQuery = """
        SELECT COUNT(*) FROM recordings 
        WHERE date >= date('now', '-7 days');
        """
        
        var statement: OpaquePointer?
        var hasHistory = false
        
        if sqlite3_prepare_v2(db, checkQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                hasHistory = sqlite3_column_int(statement, 0) > 0
            }
        }
        sqlite3_finalize(statement)
        
        // 如果已经有历史记录，就不再生成
        if hasHistory {
            return
        }
        
        // 开始事务
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        // 为过去7天每天随机生成1-3条练习记录
        for daysAgo in 1...7 {
            let recordCount = Int.random(in: 1...3)
            for _ in 0..<recordCount {
                if let item = generateRandomPracticeItem() {
                    // 生成过去的日期
                    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
                    
                    // 创建录音文件
                    let recordingId = UUID()
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let recordingsFolder = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
                    let fileURL = recordingsFolder.appendingPathComponent("\(recordingId.uuidString).m4a")
                    
                    // 创建空的录音文件
                    try? "".write(to: fileURL, atomically: true, encoding: .utf8)
                    
                    // 插入录音记录
                    let query = """
                    INSERT INTO recordings (id, practice_item_id, date, duration, file_url)
                    VALUES (?, ?, ?, ?, ?);
                    """
                    
                    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                        sqlite3_bind_text(statement, 1, (recordingId.uuidString as NSString).utf8String, -1, nil)
                        sqlite3_bind_int(statement, 2, Int32(item.id ?? 0))
                        
                        let dateFormatter = ISO8601DateFormatter()
                        let dateString = dateFormatter.string(from: date)
                        sqlite3_bind_text(statement, 3, (dateString as NSString).utf8String, -1, nil)
                        
                        let duration = Double.random(in: 30...120)
                        sqlite3_bind_double(statement, 4, duration)
                        sqlite3_bind_text(statement, 5, (fileURL.path as NSString).utf8String, -1, nil)
                        
                        if sqlite3_step(statement) != SQLITE_DONE {
                            print("Error inserting recording")
                        }
                    }
                    sqlite3_finalize(statement)
                    
                    // 随机生成评分记录
                    let scoreQuery = """
                    INSERT INTO speech_scores (recording_id, transcribed_text, match_score)
                    VALUES (?, ?, ?);
                    """
                    
                    if sqlite3_prepare_v2(db, scoreQuery, -1, &statement, nil) == SQLITE_OK {
                        sqlite3_bind_text(statement, 1, (recordingId.uuidString as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(statement, 2, (item.content as NSString).utf8String, -1, nil)
                        
                        let score = Double.random(in: 0.6...1.0)
                        sqlite3_bind_double(statement, 3, score)
                        
                        if sqlite3_step(statement) != SQLITE_DONE {
                            print("Error inserting score")
                        }
                    }
                    sqlite3_finalize(statement)
                }
            }
        }
        
        // 提交事务
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }
    
    private func generateRandomPracticeItem() -> PracticeItem? {
        let query = """
        SELECT p.*, COUNT(r.id) as recording_count
        FROM practice_items p
        LEFT JOIN recordings r ON p.id = r.practice_item_id
        GROUP BY p.id
        ORDER BY RANDOM()
        LIMIT 1;
        """
        
        var statement: OpaquePointer?
        var item: PracticeItem?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW,
               let stmt = statement {
                item = extractPracticeItem(from: stmt)
            }
        }
        sqlite3_finalize(statement)
        
        return item
    }
    
    func loadContributions(months: Int = 8) -> [[PracticeContribution?]] {
        let query = """
        WITH RECURSIVE dates(date) AS (
            SELECT date('now', 'start of day', '-\(months) months')
            UNION ALL
            SELECT date(date, '+1 day')
            FROM dates
            WHERE date < date('now', 'start of day')
        )
        SELECT 
            dates.date,
            MAX(s.match_score * 100) as max_score,
            COUNT(r.id) as practice_count
        FROM dates
        LEFT JOIN recordings r ON date(r.date) = dates.date
        LEFT JOIN speech_scores s ON r.id = s.recording_id
        GROUP BY dates.date
        ORDER BY dates.date;
        """
        
        var statement: OpaquePointer?
        var contributions: [PracticeContribution] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let dateString = String(cString: sqlite3_column_text(statement, 0))
                let score = Int(sqlite3_column_double(statement, 1))
                let count = Int(sqlite3_column_int(statement, 2))
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                if let date = dateFormatter.date(from: dateString) {
                    contributions.append(PracticeContribution(
                        id: dateString,
                        date: date,
                        score: score,
                        count: count
                    ))
                }
            }
        }
        sqlite3_finalize(statement)
        
        // 按周分组
        var weeks: [[PracticeContribution?]] = []
        var currentWeek: [PracticeContribution?] = Array(repeating: nil, count: 7)
        var currentWeekDay = 0
        
        for contribution in contributions {
            let weekday = Calendar.current.component(.weekday, from: contribution.date)
            // 转换为周一开始的索引 (1 = Monday, 7 = Sunday)
            let adjustedWeekday = (weekday + 5) % 7
            
            if adjustedWeekday < currentWeekDay {
                weeks.append(currentWeek)
                currentWeek = Array(repeating: nil, count: 7)
            }
            
            currentWeek[adjustedWeekday] = contribution
            currentWeekDay = adjustedWeekday
        }
        
        if !currentWeek.allSatisfy({ $0 == nil }) {
            weeks.append(currentWeek)
        }
        
        return weeks
    }
    
    func getContributionMonths(weeks: [[PracticeContribution?]]) -> [String] {
        var months: Set<String> = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM"
        
        for week in weeks {
            for contribution in week.compactMap({ $0 }) {
                months.insert(dateFormatter.string(from: contribution.date))
            }
        }
        
        return Array(months).sorted { month1, month2 in
            let date1 = dateFormatter.date(from: month1) ?? Date()
            let date2 = dateFormatter.date(from: month2) ?? Date()
            return date1 < date2
        }
    }
}

enum ItemFilter {
    case all
    case recent
} 
