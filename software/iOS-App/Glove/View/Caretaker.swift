import SwiftUI

struct Caretaker: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM = DataViewModel()
    @ObservedObject var medVM: MedicationViewModel
    @State private var selectedDate = Date()
    var body: some View {
        Text("Hello")
    }
}
