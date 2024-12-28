import AVFoundation

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // 停止当前朗读
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // 创建朗读配置
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 开始朗读
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    func continueSpeaking() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            // 通知 AudioManager 播放完成
            NotificationCenter.default.post(name: .TTSDidFinishSpeaking, object: nil)
        }
    }
}

// 添加通知名称
extension Notification.Name {
    static let TTSDidFinishSpeaking = Notification.Name("TTSDidFinishSpeaking")
} 