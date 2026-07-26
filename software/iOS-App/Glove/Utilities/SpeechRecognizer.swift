import AVFoundation
import Combine
import Speech

class SpeechRecognizer: ObservableObject {

    /// 辨識出的文字轉譯結果
    @Published var transcript: String = ""

    /// 目前是否正在進行語音錄音與辨識
    @Published var isRecording: Bool = false

    /// 音訊引擎實例，負責擷取麥克風輸入
    private var audioEngine: AVAudioEngine?

    /// 語音辨識請求物件，負責接收音訊緩衝區數據
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// 語音辨識任務實例
    private var task: SFSpeechRecognitionTask?

    /// 語音辨識器（預設設定為台灣繁體中文 locale）
    private let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: "zh-TW")
    )

    /// 啟動語音錄製與辨識流程
    /// - Note: 會先向系統請求語音辨識權限，獲准後才開始收音
    func startRecording() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    self.transcribe()
                } else {
                    self.transcript = "未獲得麥克風或語音辨識權限"
                }
            }
        }
    }

    /// 設定音訊引擎與發起即時語音辨識任務
    private func transcribe() {
        audioEngine = AVAudioEngine()
        request = SFSpeechAudioBufferRecognitionRequest()

        guard let audioEngine = audioEngine, let request = request,
            recognizer?.isAvailable == true
        else { return }

        // 設定是否即時回傳初步辨識結果
        request.shouldReportPartialResults = true
        isRecording = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 安裝音訊 Tap 點以即時傳輸緩衝數據至辨識請求
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { buffer, _ in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            return
        }

        // 開啟語音辨識任務
        task = recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                self.stopRecording()
            }
        }
    }

    /// 停止語音錄製、釋放音訊節點與重置辨識任務
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()

        audioEngine = nil
        request = nil
        task = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
}
