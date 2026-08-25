import Combine
import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
public class BluetoothViewModel: ObservableObject {
    
    /// 藍牙手套連線狀態
    @Published public var isConnected: Bool = false

    /// 介面呈現之連線狀態文字描述
    @Published public var connectionStatusText: String = "未連線"

    /// 裝置電量百分比（若硬體未提供則預設為 0）
    @Published public var batteryLevel: Int = 0

    /// 主要震顫頻率顯示字串（例如："5.00 Hz" 或 "--"）
    @Published public var dominantFrequencyText: String = "--"

    /// 典型震顫頻段之均方根強度 (RMS, deg/s)
    @Published public var tremorStrengthRms: Double = 0.0

    /// 手套抑制強度設定值 (0.0 至 1.0)
    @Published public var intensity: Double = 0.5 {
        didSet {
            sendIntensityToDevice(intensity)
        }
    }

    /// 震顫數據串流處理管線實例
    public let pipeline = TremorPipeline()

    /// 初始化藍牙 ViewModel 並設定資料串流回呼
    public init() {
        setupPipelineCallbacks()
    }

    /// 設定震顫處理管線之回呼監聽
    private func setupPipelineCallbacks() {
        // 綁定連線狀態變更
        pipeline.onConnectionChanged = { [weak self] connected in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = connected
                self.connectionStatusText = connected ? "已連線" : "連線中..."

                if !connected {
                    self.dominantFrequencyText = "--"
                    self.tremorStrengthRms = 0.0
                }
            }
        }

        // 綁定演算法分析結果
        pipeline.onAnalysisUpdated = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if result.dataValid {
                    self.tremorStrengthRms = result.tremorStrengthRmsDps

                    if result.frequencyReliable,
                        let freq = result.dominantFrequencyHz
                    {
                        self.dominantFrequencyText = String(
                            format: "%.2f Hz", freq)
                    } else {
                        self.dominantFrequencyText = "--"
                    }
                } else {
                    self.dominantFrequencyText = "資料不足"
                    self.tremorStrengthRms = 0.0
                }
            }
        }
    }

    /// 發送震顫抑制強度設定至硬體設備
    /// - Parameter value: 目標強度數值 (0.0 至 1.0)
    private func sendIntensityToDevice(_ value: Double) {
        // 預留供後續藍牙特徵值寫入指令使用
    }
}
