import Foundation
import SwiftData

struct MedicationRecord: Identifiable {
    let id = UUID()
    let date: Date
    let name: String
    let dose: String
}
