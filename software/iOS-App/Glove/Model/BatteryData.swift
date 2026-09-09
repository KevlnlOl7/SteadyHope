import Foundation

/// 藍牙低功耗 (BLE) 感測手套傳輸之電池狀態模型
public struct BatteryStatus {

    /// 藍牙封包類型標頭辨識碼（固定為 0x02）
    public static let bleType: UInt8 = 0x02

    /// 電池資料酬載位元組大小（4 位元組）
    public static let payloadSize = 4

    /// 完整封包位元組大小（標頭 1 位元組加上酬載 4 位元組，共 5 位元組）
    public static let packetSize = 1 + payloadSize

    /// 電池電壓數值（單位：毫伏 mV）
    public let millivolts: UInt16

    /// 電池剩餘電量百分比（數值範圍 0 至 100）
    public let percent: UInt8

    /// 電池硬體狀態旗標（包含充電中、供電異常等位元資訊）
    public let flags: UInt8

    /// 電池電壓轉換為伏特（V）之計算屬性
    public var volts: Double {
        Double(millivolts) / 1000.0
    }

    /// 解析 ESP32 傳遞之 5 位元組藍牙電池狀態原始資料
    /// - Parameter data: 接收到的原始二進位資料（包含 Byte 0 之型態標頭 0x02）
    /// - Returns: 解析完成之 BatteryStatus 結構實體，若長度不符或標頭錯誤則回傳 nil
    public static func parse(from data: Data) -> BatteryStatus? {
        guard data.count == packetSize else { return nil }
        guard data[0] == bleType else { return nil }

        let millivolts = UInt16(data[1]) | (UInt16(data[2]) << 8)
        return BatteryStatus(
            millivolts: millivolts,
            percent: data[3],
            flags: data[4]
        )
    }
}
