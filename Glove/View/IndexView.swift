import SwiftUI

struct IndexView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var medVM: MedicationViewModel
    @State private var batteryLevel: Int = 80
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
                .onTapGesture { // 點擊背景自動取消焦點
                    isInputFocused = false
                    self.hideKeyboard()
                }
            VStack(spacing: 20) {
                // 疾病階段
                VStack(alignment: .center) {
                    Text("疾病階段")
                        .font(.system(size: 20, weight: .bold))
                        .padding(5)
                    if let user = loginVM.userData {
                        Text("\(user.diseaseStage)")
                            .font(.system(size: 30, weight: .bold))
                    } else {
                        Text("無資料,請至個人資料修改")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundColor(.gray)
                            
                    }
                    Spacer()
                }
                .padding()
                .frame(width: 350, height: 120)
                .background(Color.white)
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)

                HStack(spacing: 15) {
                    // 電量
                    VStack(alignment: .leading) {
                        HStack {
                            BatteryIcon(level: batteryLevel)
                            Spacer()
                        }
                        Spacer()
                        HStack(alignment: .bottom, spacing: 2) {
                                Text("\(batteryLevel)")
                                    .font(.system(size: 60, weight: .medium))
                                Text("%")
                                    .font(.system(size: 30))
                                    .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity,alignment: .trailing)
                    }
                    .padding()
                    .frame(width: 165, height: 165)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                    
                    // 上次抖動時間
                    VStack(alignment: .leading,spacing: 6) {
                        HStack(alignment: .bottom, spacing: 2) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 15))
                                .foregroundColor(.blue)
                            Text(" 上次抖動時間")
                                .font(.system(size: 15))
                                .bold()
                        }
                        .frame(maxWidth: .infinity,alignment: .leading)
                        Spacer()
                        
                        HStack(alignment: .bottom, spacing: 2) {
                            Text(dataVM.lastVibrationDate)
                                .font(.system(size: 30, weight: .medium))
                                .bold()
                        }
                        .padding(.leading, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(alignment: .bottom) {
                            Text(dataVM.lastVibrationTime)
                                .font(.system(size: 40, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        Spacer()
                        
                    }
                    .padding()
                    .frame(width: 165, height: 165)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack{
                        Text("用藥資料")
                            .font(.system(size: 16))
                            .bold()
                        Spacer()
                        
                        NavigationLink(destination: MedicationView(medVM: medVM)) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                    .padding(.bottom, 8)
                    
                    // 輸入區域
                    VStack(spacing: 10) {
                        HStack {
                            DatePicker("", selection: $medVM.inputDate,in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .scaleEffect(0.9)
                                .frame(width: 200)
                            Spacer()
                        }
                        
                        HStack(spacing: 10) {
                            TextField("藥名", text: $medVM.inputName)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                            
                            TextField("用量", text: $medVM.inputDose)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            TextField("單位", text: $medVM.inputUnit)
                                .focused($isInputFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Button(action: {
                                self.hideKeyboard()
                                isInputFocused = false
                                if !medVM.inputName.isEmpty {
                                    medVM.addRecord()
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(medVM.inputName.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                            }
                            .disabled(medVM.inputName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 10)
                    Divider()
                    
                    // 內容滾動區
                    ScrollView {
                        VStack(spacing: 0) {
                            if medVM.medicationList.isEmpty {
                                Text("目前尚無資料")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 40)
                                    .frame(maxWidth: .infinity)
                            }else{
                                ForEach(medVM.medicationList.prefix(5)) { med in
                                    medicationRow(
                                        date: medVM.formatDate(med.date, format: "M/d"),
                                        time: medVM.formatDate(med.date, format: "HH:mm"),
                                        name: med.name,
                                        dose: med.dose,
                                        showDivider: true
                                    )
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(width: 350, height: 330)
                .background(Color.white)
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                .onTapGesture { // 點擊背景自動取消焦點
                    isInputFocused = false
                    self.hideKeyboard()
                }
                
                Spacer()
            }
            .offset(y: isInputFocused ? -100 : 0)
            .animation(.easeInOut(duration: 0.3), value: isInputFocused)
            .padding(.top, 30)
        }
        .onDisappear { // 切換頁面自動取消焦點
            isInputFocused = false
            self.hideKeyboard()
        }
    }
}
