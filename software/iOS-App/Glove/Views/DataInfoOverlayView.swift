import SwiftUI

enum InfoSheetType: Identifiable {
    case dataAndRules
    case frequency
    case rms
    case chart
    case eventRMSTrend
    case eventPSD

    var id: Self { self }

    var title: String {
        switch self {
        case .dataAndRules:
            return "資料與判斷方式說明"
        case .frequency:
            return "主要震動頻率說明"
        case .rms:
            return "震動強度（RMS）說明"
        case .chart:
            return "即時走勢圖與操作說明"
        case .eventRMSTrend:
            return "前後 3 秒動作分析強度走勢說明"
        case .eventPSD:
            return "PSD 頻譜與震顫分佈說明"
        }
    }
}

struct DataInfoOverlayView: View {
    let type: InfoSheetType
    @Binding var activeInfoSheet: InfoSheetType?
    @AppStorage("isSimpleModeEnabled") private var isSimpleMode: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Color.black.opacity(0.35)
                )
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
                        .foregroundColor(AppTheme.primary(for: colorScheme))

                    Text(
                        isSimpleMode && (type == .frequency || type == .rms)
                        ? (type == .frequency ? "震顫節奏說明" : "抖動幅度說明")
                        : type.title
                    )
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeInfoSheet = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch type {
                        case .dataAndRules:
                            dataAndRulesExplanationSection
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
                .frame(maxHeight: 380)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeInfoSheet = nil
                    }
                } label: {
                    Text("我知道了")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.primary(for: colorScheme))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(20)
            .background(
                AppTheme.cardBackground(for: colorScheme)
                    .opacity(0.96)
            )
            .cornerRadius(24)
            .padding(.horizontal, 20)
            .shadow(
                color: Color.black.opacity(0.2),
                radius: 20,
                x: 0,
                y: 10
            )
        }
    }

    private var dataAndRulesExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("測量說明與注意事項")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 裝置記錄配戴部位動作訊號，呈現頻率與角速度強度，供日常觀察與回診溝通參考。")
                    Text("• 頻率顯示「--」時，可能是資料不足、中斷，或暫時沒有清楚的主要頻率；不代表一定沒有抖動。")
                    Text("• 裝置作動標記表示控制鏈套用非零命令的時段，不能直接當作震顫開始、結束或改善程度。")
                    Text("• 本頁數據不能單獨判定病程、疾病嚴重度或服藥療效。")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("App 頻率可信度（軟體分析）")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 搜尋頻帶：3–7 Hz（FFT bin 12–28）候選主峰")
                    Text("• vector RMS：三軸去平均整體 RMS ≥ 0.20 deg/s")
                    Text("• 頻帶佔比：P(3–7 Hz) / P(0.5–15 Hz) ≥ 0.30")
                    Text("• 主峰集中度：主峰前後 ±0.5 Hz（共 5 個頻率格）佔 3–7 Hz 功率 ≥ 0.45")
                    Text("• 三項條件同時成立才回報主要頻率")
                    Text("• 未達標時仍可保留有效 4–6 Hz RMS，主要頻率顯示「--」")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("硬體 Gate（參考工程配置）")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 輸入：單軸角速度，名目 100 Hz；目前核對版本使用 X 軸")
                    Text("• 4–6 Hz 與 1–3 Hz 經因果帶通後形成衰減峰值包絡")
                    Text("• 啟動：4–6 Hz 包絡 ≥ 6 deg/s 且比例 ≥ 0.55，連續 20 筆（約 200 ms）")
                    Text("• 解除：包絡 < 3 deg/s 或比例 < 0.45，連續 15 筆（約 150 ms）")
                    Text("• 中間區域保留既有狀態，異常輸入或控制故障另行停止")
                    Text("• 此包絡不是 App RMS；Gate 也不等於患者震顫事件或抑震成功")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("版本與狀態核對")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("演算法規格：2026-09-12 修訂版｜實際裝置燒錄版本與配置：待確認")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, 4)
        }
    }

    private var simpleFrequencyExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("這個數字代表什麼？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("這個數字表示動作訊號中主要頻率的變化速度，可以簡單理解為每秒大約出現幾次週期性的變化。")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("怎麼看？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 數字越高，代表主要週期變化越快。")
                    Text("• 4–6 Hz 是本系統核心震顫頻帶的工程分析範圍之一。")
                    Text("• 顯示「--」時，不代表一定沒有抖動；可能是資料不足、中斷，或沒有通過主要頻率可信度條件。")
                }
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private var simpleRMSExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("這個數字代表什麼？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("RMS 是用來表示 4–6 Hz 頻帶內角速度訊號強度的數值。數值較大，表示該分析視窗內的訊號變化幅度較大。")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("怎麼看？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 數值接近 0，代表目前這個分析頻帶的訊號較小。")
                    Text("• 數值提高，代表指定頻帶中的角速度訊號較強。")
                    Text("• RMS 本身不是疾病嚴重度分級，也不能只靠單一數值判定是否發生震顫事件。")
                }
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
            }
        }
    }

    private var frequencyExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("定義與來源")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("系統將 4 秒、100 Hz 的三軸角速度資料分別去平均、套用 Hann window，再執行 400 點 FFT 與 PSD 分析。主要頻率候選值在 3–7 Hz 之間搜尋。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("可靠度門檻（防止不可靠頻率被誤顯示）")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("• vector RMS：三軸去平均整體 RMS ≥ 0.20 deg/s")
                    Text("• 3–7 Hz 功率需佔 0.5–15 Hz 功率至少 30%")
                    Text("• 主峰前後 ±0.5 Hz 功率需佔 3–7 Hz 功率至少 45%")
                    Text("• 三項條件必須同時成立才回報主要頻率")
                    Text("• 未達門檻時，RMS 可以保留，但主要頻率顯示「--」")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("重要限制")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("上述頻率範圍與判斷條件為目前研究原型的工程分析規則，不是疾病診斷門檻，也不能單獨用來判定帕金森氏症、原發性震顫或其他疾病。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
    }

    private var rmsExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("定義")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("RMS（Root Mean Square，均方根值）用於量化指定 4–6 Hz 頻帶內角速度訊號的強度，單位為 deg/s。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("計算方式")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("RMS = √[ Σ₄₋₆Hz PSD × Δf ]")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.background(for: colorScheme))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("參數規格")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 取樣率（Fs）：100 Hz")
                    Text("• 分析視窗（N）：400 筆，約 4 秒")
                    Text("• 更新頻率：每累積 50 筆新資料更新一次（約 0.5 秒）")
                    Text("• 頻率解析度（Δf）：100 / 400 = 0.25 Hz")
                    Text("• RMS 是強度指標，不是疾病嚴重度分級")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private var chartExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("圖表操作")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("點擊資料點跳轉")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Text("點擊走勢圖上的動作分析紀錄點（橘點變紅），下方列表會自動滾動並展開該筆詳細資料。")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("左右滑動檢視")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Text("左右滑動可查看不同時間的資料。")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("雙指縮放時間範圍")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Text("可放大查看細部波動（最小 3 秒），或縮小查看長時段走勢（最大 24 小時）。")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("選擇時間")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Text("可直接跳至指定時間查看資料。今天的資料最多只能選到目前時間。")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("回到現在")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Text("可以返回今天的目前時間，重新查看最新即時資料。")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
                .padding(10)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("圖表與資料標記")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(AppTheme.primary(for: colorScheme))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        Text("藍色折線：4–6 Hz RMS 強度之時間連續走勢。")
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        Text("橙色圓點：該時段保存之動作分析紀錄。點擊選中後會轉為紅點並放大。")
                    }

                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 9, height: 9)
                            .padding(.top, 3)

                        Text("橙色背景：馬達命令作用區間（控制鏈套用非零命令時段；不等於原始 Gate 或抑震成功）。")
                    }
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private var eventRMSTrendExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("前後 3 秒震動強度（RMS）走勢")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("圖表以指定動作分析紀錄時間為中心，呈現前 3 秒至後 3 秒的 4–6 Hz RMS 變化。這裡呈現的是分析資料趨勢，不代表已完成患者事件起迄判定。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("圖表標記說明")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 選取點：目前查看中的動作分析紀錄點。")
                    Text("• 走勢折線：該分析視窗鄰近時間範圍內的 RMS 連續計算結果。")
                    Text("• 控制命令標記：若有顯示，只代表控制鏈套用命令之時段，不能推論為震顫停止或抑震有效。")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private var psdExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("功率譜密度（Power Spectral Density）")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("系統以 4 秒、100 Hz 的三軸角速度資料進行 FFT／PSD 分析，將時域訊號轉換為不同頻率的功率分佈。頻率解析度為 0.25 Hz。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("分析頻帶與標記")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                VStack(alignment: .leading, spacing: 6) {
                    Text("• 3–7 Hz：主要頻率候選搜尋範圍。")
                    Text("• 4–6 Hz：核心震顫強度 RMS 計算頻帶。")
                    Text("• 主要頻率只有在資料品質與頻率可信度條件成立時才會顯示。")
                    Text("• 「--」表示目前沒有可可靠回報的主要頻率，不代表一定沒有抖動。")
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(10)
            }
        }
    }
}
