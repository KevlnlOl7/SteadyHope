import SwiftUI

/// 電池 Icon
struct BatteryIcon: View {
    var level: Int
    var body: some View {
        ZStack(alignment: .leading) {
            // 外框
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.black, lineWidth: 1.5)
                .frame(width: 25, height: 12)
            
            // 內部電量條
            RoundedRectangle(cornerRadius: 1)
                .fill(level >= 80 ? Color.green : (level <= 20 ? Color.red : Color.yellow))
                .frame(width: CGFloat(min(max(level, 0), 100)) / 100 * 21, height: 8)
                .offset(x: 2)
            
            // 電池頭
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black)
                .frame(width: 2, height: 5)
                .offset(x:27)
        }
    }
}
