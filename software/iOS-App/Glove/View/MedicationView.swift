import SwiftUI

struct MedicationView: View {

    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var medVM: MedicationViewModel
    @FocusState private var isInputFocused: Bool
    @State private var filterDate = Date()
    @State private var isShowingAll: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
                .onTapGesture {
                    isInputFocused = false
                    hideKeyboard()
                }

            VStack(spacing: 0) {
                if loginVM.userData?.role == 0{
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("新增健康與用藥紀錄")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        VStack(spacing: 14) {
                            // 時間選擇
                            HStack {
                                Text("時間")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                DatePicker(
                                    "選擇時間",
                                    selection: $medVM.inputDate,
                                    in: ...Date()
                                )
                                .labelsHidden()
                                .scaleEffect(0.9)
                                Spacer()
                            }
                            
                            Divider()
                            
                            // 用藥資訊
                            VStack(alignment: .leading, spacing: 6) {
                                Text("用藥")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                HStack(spacing: 8) {
                                    TextField("藥品名稱", text: $medVM.inputName)
                                        .focused($isInputFocused)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("用量", text: $medVM.inputDose)
                                        .focused($isInputFocused)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                    
                                    TextField("單位", text: $medVM.inputUnit)
                                        .focused($isInputFocused)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                }
                            }
                            
                            Divider()
                            
                            // 生理數據 (血壓、血糖、體溫、體重)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("生理量測")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                HStack(spacing: 8) {
                                    TextField("收縮壓", text: $medVM.inputSystolicBP)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Text("/")
                                        .foregroundColor(.gray)
                                    
                                    TextField("舒張壓", text: $medVM.inputDiastolicBP)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("血糖", text: $medVM.inputBloodSugar)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack(spacing: 8) {
                                    TextField("體溫 (°C)", text: $medVM.inputBodyTemp)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("體重 (kg)", text: $medVM.inputBodyWeight)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .focused($isInputFocused)
                            
                            Divider()
                            
                            // 日常作息 (睡眠、食量)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("日常作息")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                HStack(spacing: 8) {
                                    TextField("睡眠 (時)", text: $medVM.inputSleepHours)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("食量 (如:正常/少食)", text: $medVM.inputFoodAmount)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .focused($isInputFocused)
                            
                            // 新增按鈕
                            Button(action: {
                                isInputFocused = false
                                hideKeyboard()
                                if let uid = loginVM.userData?.userID,
                                   let token = AuthManager.shared.getToken() {
                                    medVM.addRecord(currentUserID: uid, token: token)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("新增紀錄")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            .padding(.top, 6)
                        }
                        .padding([.horizontal, .bottom])
                    }
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
                    .padding()
                }
                .frame(maxHeight: 320) // 控制輸入卡片的最大高度，避免擋住下方清單
            }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("依日期查詢")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        DatePicker(
                            "",
                            selection: $filterDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .onChange(of: filterDate) { _, newValue in
                            withAnimation {
                                isShowingAll = false
                            }
                            print("篩選日期改為: \(newValue)")
                        }

                        Spacer()

                        Button(isShowingAll ? "依日期顯示" : "顯示全部") {
                            withAnimation {
                                isShowingAll.toggle()
                            }
                            
                            Task {
                                if isShowingAll {
                                    await medVM.loadRecords(for: "")
                                } else {
                                    let dateString = filterDate.toString(format: "yyyy-MM-dd")
                                    await medVM.loadRecords(for: dateString)
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }

                List {
                    Section(header: Text(dateSectionTitle)) {
                        if medVM.medicationList.isEmpty {
                            Text("目前尚無資料")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(filteredRecords) { med in
                                medicationRow(
                                    date: med.date.toString(format: "M/d"),
                                    time: med.date.toString(format: "HH:mm"),
                                    name: med.name,
                                    dose: med.dose
                                )
                                .listRowBackground(Color.white)
                            }
                            .onDelete { offsets in
                                medVM.deleteRecord(
                                    records: filteredRecords,
                                    at: offsets
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("健康與用藥資料")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let today = Date().toString(format: "yyyy-MM-dd")
            await medVM.loadRecords(for: today)
        }
        .onChange(of: filterDate) { _, newValue in
            Task {
                let dateString = newValue.toString(format: "yyyy-MM-dd")
                await medVM.loadRecords(for: dateString)
            }
        }
    }

    private var filteredRecords: [MedicationRecord] {
        if isShowingAll {
            return medVM.medicationList
        } else {
            return medVM.medicationList.filter { record in
                Calendar.current.isDate(record.date, inSameDayAs: filterDate)
            }
        }
    }

    private var dateSectionTitle: String {
        if isShowingAll {
            return "歷史紀錄"
        } else {
            return Calendar.current.isDateInToday(filterDate)
                ? "今日紀錄" : filterDate.toString(format: "M/d 紀錄")
        }
    }
}
