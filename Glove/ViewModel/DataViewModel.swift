import Foundation
import Combine

class DataViewModel: ObservableObject {
    
    /// 平均震動強度
    var avgStrength: Double {
        return 0.0 // 暫時先回傳 0
    }
    
    /// 最高震幅
    var maxStrength: Double {
        return 0.0 // 暫時先回傳 0
    }
    
    /// 最後震動日期
    var lastVibrationDate: String {
        return "--/--"
    }

    /// 最後震動時間
    var lastVibrationTime: String {
        return "--/--"
    }
    
}
