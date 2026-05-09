import SwiftUI

struct MedicationView: View {
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("新增紀錄")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    VStack(spacing: 12) {
                        HStack {
                            DatePicker("選擇時間", selection: $medVM.inputDate,in: ...Date())
                                .labelsHidden()
                                .scaleEffect(0.9)
                            Spacer()
                        }
                        
                        HStack(spacing: 10) {
                            TextField("藥品名稱", text: $medVM.inputName)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("用量", text: $medVM.inputDose)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                            
                            TextField("單位", text: $medVM.inputUnit)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                            
                            Button(action: {
                                isInputFocused = false
                                hideKeyboard()
                                if !medVM.inputName.isEmpty {
                                    medVM.addRecord()
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(medVM.inputName.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                            }
                            .disabled(medVM.inputName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
                .background(Color.white)
                .cornerRadius(15)
                .padding()
                .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("依日期查詢")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        DatePicker("", selection: $filterDate,in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: filterDate) { oldValue,newValue in
                                withAnimation {
                                            isShowingAll = false
                                        }
                                print("篩選日期改為: \(newValue)")
                            }
                        
                        Spacer()
                        
                        Button("顯示全部") {
                            withAnimation {
                                    isShowingAll.toggle()
                                }
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
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
                                    date: medVM.formatDate(med.date, format: "M/d"),
                                    time: medVM.formatDate(med.date, format: "HH:mm"),
                                    name: med.name,
                                    dose: med.dose
                                )
                                .listRowBackground(Color.white)
                            }
                            .onDelete { offsets in
                                medVM.deleteRecord(records: filteredRecords, at: offsets)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("用藥資料")
        .navigationBarTitleDisplayMode(.inline)
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
            // 如果選的是今天，顯示今日紀錄，否則顯示選取的日期
            return Calendar.current.isDateInToday(filterDate) ? "今日紀錄" : medVM.formatDate(filterDate, format: "M/d 紀錄")
        }
    }
}
