import Foundation
import AVFoundation

class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = AudioManager()
    
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var currentRecordingURL: URL?
    @Published var currentPlayingURL: URL?
    @Published var isUsingTTS = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var streamingPlayer: AVPlayer?
    private var timer: Timer?
    private let ttsManager = TTSManager.shared
    
    override init() {
        super.init()
        setupAudioSession()
        // 添加 TTS 完成通知观察者
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ttsDidFinishSpeaking),
            name: .TTSDidFinishSpeaking,
            object: nil
        )
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            print("Audio session setup successful")
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    // 播放示例音频（流媒体）
    func playStreamingAudio(url: String) {
        print("🎵 开始播放流媒体音频: \(url)")
        guard let audioUrl = URL(string: url) else {
            print("❌ 无效的URL: \(url)")
            return
        }
        
        // 停止所有正在播放的音频
        stopAllAudio()
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            
            let playerItem = AVPlayerItem(url: audioUrl)
            streamingPlayer = AVPlayer(playerItem: playerItem)
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(streamingPlayerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
            streamingPlayer?.play()
            isPlaying = true
            currentRecordingURL = nil
            print("✅ 开始播放流媒体音频")
        } catch {
            print("❌ 播放流媒体音频失败: \(error)")
        }
    }
    
    // 播放录音文件
    func playRecording(url: URL) {
        print("🎵 开始播放录音: \(url)")
        // 停止所有正在播放的音频
        stopAllAudio()
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            currentRecordingURL = url
            print("✅ 开始播放录音")
        } catch {
            print("❌ 播放录音失败: \(error)")
        }
    }
    
    func startRecording() -> URL? {
        stopAllAudio()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        // 创建录音文件夹
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        
        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = recordingsFolder.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            
            startTimer()
            print("Recording started at: \(fileURL)")
            return fileURL
        } catch {
            print("Recording failed: \(error)")
            return nil
        }
    }
    
    func stopRecording() -> TimeInterval {
        audioRecorder?.stop()
        isRecording = false
        stopTimer()
        
        let duration = currentTime
        currentTime = 0
        return duration
    }
    
    func stopPlaying() {
        if isUsingTTS {
            ttsManager.stopSpeaking()
            isUsingTTS = false
        } else {
            stopAllAudio()
        }
        isPlaying = false
    }
    
    private func stopAllAudio() {
        print("⏹️ 停止所有音频播放")
        // 停止录音播放
        audioPlayer?.stop()
        audioPlayer = nil
        
        // 停止流媒体播放
        streamingPlayer?.pause()
        streamingPlayer = nil
        
        isPlaying = false
        currentRecordingURL = nil
    }
    
    @objc private func streamingPlayerDidFinishPlaying() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentRecordingURL = nil
        }
        print("✅ 流媒体音频播放完成")
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime += 0.1
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - AVAudioRecorderDelegate
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        print("Recording finished, success: \(flag)")
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentRecordingURL = nil
        }
        print("✅ 录音播放完成")
    }
    
    // 添加本地音频播放方法
    func playLocalAudio(url: URL) {
        print("🎵 开始播放本地音频: \(url)")
        stopAllAudio()
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            currentPlayingURL = url
            print("✅ 开始播放本地音频")
        } catch {
            print("❌ 播放本地音频失败: \(error)")
        }
    }
    
    func playContent(_ content: String) {
        isUsingTTS = true
        ttsManager.speak(content)
        isPlaying = true
    }
    
    @objc private func ttsDidFinishSpeaking() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isUsingTTS = false
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 