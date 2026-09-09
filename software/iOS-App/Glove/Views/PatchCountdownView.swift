import SwiftUI

/// 貼片黏貼按壓 30 秒倒數計時提示
struct PatchCountdownView: View {
    /// 倒數完成或略過確認時之回呼處理常式
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 剩餘倒數秒數（預設 30 秒）
    @State private var timeRemaining: Int = 30

    /// 計時器運作狀態
    @State private var isTimerRunning: Bool = false

    /// 內部排程計時器實例
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.6))
                .ignoresSafeArea()

            // 右上角關閉按鈕
            VStack {
                HStack {
                    Spacer()
                    Button {
                        timer?.invalidate()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                    }
                }
                Spacer()
            }

            VStack(spacing: 24) {
                Text("用手掌按緊貼片")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("請用手掌均勻按壓貼片 30 秒鐘\n使其在皮膚上黏貼牢固")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))

                // 圓環進度動畫區域
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 16)
                        .frame(width: 180, height: 180)

                    Circle()
                        .trim(from: 0, to: CGFloat(timeRemaining) / 30.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1.0), value: timeRemaining)

                    Text("\(timeRemaining)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 10)

                if !isTimerRunning {
                    Button {
                        startTimer()
                    } label: {
                        Text("開始 30 秒倒數")
                            .font(.title3.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(30)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("請持續按壓...")
                            .font(.headline)
                            .foregroundColor(.green)

                        Button {
                            timer?.invalidate()
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            onComplete()
                        } label: {
                            Text("已按壓牢固，直接完成紀錄")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .underline()
                        }
                    }
                }
            }
            .padding(30)
            .background(Color.white.opacity(0.15))
            .cornerRadius(24)
            .padding(.horizontal, 20)
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    /// 啟動 30 秒倒數計時排程
    private func startTimer() {
        isTimerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 1 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                onComplete()
            }
        }
    }
}
