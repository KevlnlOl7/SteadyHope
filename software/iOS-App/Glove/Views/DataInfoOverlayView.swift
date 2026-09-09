import SwiftUI

enum InfoSheetType: Identifiable {
    case frequency
    case rms
    case chart
    case eventRMSTrend
    case eventPSD

    var id: Self { self }

    /// 各說明類型預設之導覽列標題文字
    var title: String {
        switch self {
        case .frequency: return "主要震動頻率說明"
        case .rms: return "震動強度 (RMS) 說明"
        case .chart: return "即時走勢圖與操作說明"
        case .eventRMSTrend: return "前後 3 秒震動強度 (RMS) 走勢說明"
        case .eventPSD: return "PSD 頻譜與震顫分佈說明"
        }
    }
}

struct DataInfoOverlayView: View {
    /// 當前欲展示之說明主題類型
    let type: InfoSheetType

    @Binding var activeInfoSheet: InfoSheetType?

    /// 讀取本地簡易模式開關狀態
    @AppStorage("isSimpleModeEnabled") private var isSimpleMode: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeInfoSheet = nil
                    }
                }

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text(isSimpleMode && (type == .frequency || type == .rms) ? (type == .frequency ? "震顫節奏說明" : "抖動幅度說明") : type.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeInfoSheet = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch type {
                        case .frequency:
                            if isSimpleMode {
                                simpleFrequencyExplanationSection
                            } else {
                                frequencyExplanationSection
                            }
                        case .rms:
                            if isSimpleMode {
                                simpleRMSExplanationSection
                            } else {
                                rmsExplanationSection
                            }
                        case .chart:
                            chartExplanationSection
                        case .eventRMSTrend:
                            eventRMSTrendExplanationSection
                        case .eventPSD:
                            psdExplanationSection
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 330)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeInfoSheet = nil
                    }
                }) {
                    Text("我知道了")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(20)
            .background(Color(.systemBackground).opacity(0.96))
            .cornerRadius(24)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }

    /// 簡易模式專屬說明區塊：震顫節奏（頻率）
    private var simpleFrequencyExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("這個數字代表什麼？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.blue)

                Text("就像手在跟著拍子抖動一樣，這個數字代表手「一秒鐘大概抖了幾下」。")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("數字大概是多少？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 4 到 6：手放鬆時最常出現的規律抖動拍子。")
                    Text("• 7 以上：動作比較快的小碎抖，通常像緊張或手用力端東西時出現。")
                    Text("• 顯示「--」：代表手很放鬆平穩、沒有明顯抖動，不用擔心！")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    /// 簡易模式專屬說明區塊：抖動幅度（RMS）
    private var simpleRMSExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("這個數字代表什麼？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.blue)

                Text("代表手抖動時「力道有多大、晃得多厲害」。數字越小越平靜，數字越大表示手晃動得越明顯。")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("怎麼看目前的狀況？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 數字很小（接近 0.00）：手部很穩定，幾乎沒有晃動。")
                    Text("• 數字超過 0.20：手部開始有比較明顯的抖動，系統會自動在下方記錄下這一次的時間，方便回頭看！")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    /// 標準模式說明區塊：主要震動頻率之訊號處理與臨床判定
    private var frequencyExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("定義與來源")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                Text("系統將 4 秒 (400 筆) 三軸角速度訊號經 Hann 窗與 FFT 計算出 PSD 功率譜密度，並在 3–7 Hz 震顫帶內搜尋能量最強的峰值 (Peak)，換算為主要震動頻率 (Hz)。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("可靠度門檻（防亂顯示機制）")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 震顫強度：三軸向量強度需 ≥ 0.20 deg/s")
                    Text("• 頻帶佔比：3–7 Hz 能量需佔總能量 30% 以上")
                    Text("• 峰值集中度：主峰前後 0.5 Hz 需佔震顫帶 45% 以上")
                    Text("• 未達門檻時顯示「--」，避免將日常動作雜訊誤判為震顫")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("臨床判讀區間")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 4 – 6 Hz：帕金森氏症常見之典型靜止型震顫")
                    Text("• 5 – 8 Hz：常見於原發性震顫或姿勢型震顫")
                    Text("• 8 – 12 Hz：生理性震顫（如緊張、疲勞引發之抖動）")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    /// 標準模式說明區塊：RMS 震顫強度數學定義與取樣參數
    private var rmsExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("定義")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                Text("RMS（Root Mean Square，均方根值）用於量化手部角速度在 4–6 Hz 核心震顫帶內的總能量與晃動幅度，單位為 deg/s。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("計算公式")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                Text("RMS = √[ Σ₄₋₆Hz (PSDx + PSDy + PSDz) × Δf ]")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("參數規格")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 取樣率 (Fs)：100 Hz (每秒 100 筆)")
                    Text("• 分析視窗 (N)：400 筆資料 (4 秒滑動視窗)")
                    Text("• 更新頻率：每累積 50 筆新資料 (0.5 秒) 更新一次")
                    Text("• 頻率解析度 (Δf)：100 Hz / 400 = 0.25 Hz")
                    Text("• 事件門檻：≥ 0.20 deg/s 自動記錄為顯著震顫事件")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    /// 說明區塊：即時走勢圖手勢互動與視覺圖示定義
    private var chartExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("圖表操作")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("點擊數據點跳轉")
                                .font(.system(size: 13, weight: .bold))

                            Text("點擊走勢圖上的顯著震顫點，下方事件清單會自動展開，並滾動至最接近該時間的震顫事件。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("左右滑動檢視")
                                .font(.system(size: 13, weight: .bold))

                            Text("左右滑動可查看不同時間的震動資料，滑動距離會對應圖表時間範圍。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("雙指放大")
                                .font(.system(size: 13, weight: .bold))

                            Text("在圖表上用雙指向外拉，可以放大時間範圍，查看更細部的震動變化，最小可視時間範圍約為 3 秒。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("雙指縮小")
                                .font(.system(size: 13, weight: .bold))

                            Text("在圖表上用雙指向內捏，可以縮小時間範圍，一次查看更長時間的震動趨勢。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("選擇時間")
                                .font(.system(size: 13, weight: .bold))

                            Text("點擊「選擇時間」可以直接跳至指定時段查看資料。今天的資料最多只能選到目前時間。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("回到現在")
                                .font(.system(size: 13, weight: .bold))

                            Text("今天查看歷史時間後，可在「選擇時間」視窗中點擊「回到現在」，恢復即時自動追蹤最新資料。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("波形與視覺標記")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.50, blue: 0.96))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        Text("藍色折線：每 0.5 秒計算一次的 4–6 Hz RMS 震顫強度走勢，呈現原始數據變化。")
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        Text("橙色圓點：顯著震顫事件點（≥ 0.20 deg/s），點擊後可跳轉至下方對應事件。")
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        Text("紅色圓點：目前選取的震顫資料點，代表你剛剛點擊的數據位置。")
                    }

                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 9, height: 9)
                            .padding(.top, 3)

                        Text("橙色柱狀背景：硬體感測器回傳的抑震馬達啟動運轉區間。")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    /// 說明區塊：震顫事件前後 3 秒高解析走勢圖分析意義
    private var eventRMSTrendExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("前後 3 秒震動強度 (RMS) 走勢")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                Text("截取該震顫事件發作當下「前 3 秒至後 3 秒（共 6 秒高解析區間）」的連續 4–6 Hz RMS 強度真實折線，聚焦於發作瞬間的急遽起伏與抑震馬達介入反應。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("圖例標記說明")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 紅色圓點：本事件捕捉當下的核心發作點。")
                    Text("• 橙色圓點：前後 3 秒內其他達標（≥ 0.20 deg/s）的顯著震顫點。")
                    Text("• 橙色柱狀背景：抑震馬達啟動區間，可即時檢視馬達啟動後強度是否有迅速壓降。")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    /// 說明區塊：PSD 功率譜密度圖分析原理與頻段意義
    private var psdExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("功率譜密度 (Power Spectral Density)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                Text("對 4 秒三軸角速度施加 Hann 窗後執行 400 點 FFT，將時域波形轉換為頻域能量分佈，單位為 (deg/s)²/Hz，頻率間距 Δf = 0.25 Hz。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("分析頻帶與標記")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 3 – 7 Hz（紫色背景）：搜尋震顫主要頻率的候選分析區間 (bin 12–28)。")
                    Text("• 4 – 6 Hz：核心震顫強度積分帶 (bin 16–24)，用以計算 RMS 數值。")
                    Text("• 紅色虛線 (主峰 Peak)：通過可靠度驗證之主要震顫頻率點。")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }
}
