import SwiftUI

/// 操作步驟資料模型
struct GuideStep: Identifiable {
    let id = UUID()
    let stepNumber: Int
    let title: String
    let description: String
    let imageAssetName: String?
    let placeholderPrompt: String
}

/// 指南單元項目
struct GuideTopic: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let systemIcon: String
    let steps: [GuideStep]
}

/// 指南核心分類（貼近使用者直覺生活語言）
enum GuideCategory: String, CaseIterable, Identifiable {
    case all = "全部指南"
    case account = "帳號與身分"
    case homeAndGlove = "手套連線與日常"
    case tremor = "震顫分析與紀錄"
    case moodBoard = "家人心情便利貼"
    case medication = "用藥與貼片管理"
    case healthAndAssessment = "健康自評與體徵"
    case reminderAndReport = "提醒設定與就診報告"
    case familyShare = "家屬互相連結"
    case aiAssistant = "隨身健康小助手"

    var id: String { self.rawValue }

    var iconName: String {
        switch self {
        case .all: return "list.bullet.rectangle"
        case .account: return "person.crop.circle"
        case .homeAndGlove: return "hand.wave.fill"
        case .tremor: return "waveform.path.ecg"
        case .moodBoard: return "note.text"
        case .medication: return "pills.fill"
        case .healthAndAssessment: return "heart.text.square.fill"
        case .reminderAndReport: return "doc.text.fill"
        case .familyShare: return "person.2.fill"
        case .aiAssistant: return "sparkles"
        }
    }
}

struct GuideRepository {
    static let topics: [GuideCategory: [GuideTopic]] = [
        .account: [
            GuideTopic(
                title: "如何登入與註冊帳號",
                summary: "依照病患或照護者身分建立帳號，保障個人資料與健康紀錄安全。",
                systemIcon: "person.badge.shield.checkmark",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "登入個人帳號",
                        description: "打開 App 後，輸入您註冊的電子信箱與密碼，按下「登入」即可進入首頁。系統會確認帳號與密碼是否相符。",
                        imageAssetName: "guide_login_screen",
                        placeholderPrompt: "預留畫面：登入畫面，包含信箱與密碼輸入框"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "選擇適合的身分註冊",
                        description: "初次使用請點選註冊，並選擇「病患」或「照護者」身分。若您是病患，會多一欄「疾病階段」供您填寫，幫助系統更貼切掌握您的身體狀況。",
                        imageAssetName: "guide_register_role",
                        placeholderPrompt: "預留畫面：註冊頁面切換病患與照護者身分"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "填寫基本資料與設定密碼",
                        description: "依序填入姓名、信箱、生日、性別與密碼。密碼至少需要 8 個字元，並同時包含「大寫英文、小寫英文與數字」（例如 Steady2026），也可以加入特殊符號增加安全性。",
                        imageAssetName: "guide_register_fields",
                        placeholderPrompt: "預留畫面：基本資料填寫表單與密碼強度提示"
                    )
                ]
            ),
            GuideTopic(
                title: "修改個人資料與密碼",
                summary: "若個人資料有變更或需要更換密碼，可隨時在個人設定中調整。",
                systemIcon: "person.crop.circle.badge.checkmark",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "進入個人設定",
                        description: "點擊左上方選單進入個人資料區，即可查看目前的姓名與信箱，並直接修改個人資料或重設新密碼。",
                        imageAssetName: "guide_profile_edit",
                        placeholderPrompt: "預留畫面：個人資料修改與變更密碼介面"
                    )
                ]
            )
        ],

        .homeAndGlove: [
            GuideTopic(
                title: "認識首頁資訊",
                summary: "一開 App 就能掌握看病前準備、手套電量、上次發作時間與今日服藥進度。",
                systemIcon: "house.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "看病前準備與即時狀態",
                        description: "首頁最上方會顯示您事先生成由 AI 整理的「看病前準備」備忘。中間可一眼看見手套剩餘電量與上次抖動時間。點擊電量會帶您前往手套調整設定；點擊上次抖動時間則會開啟震動記錄圖表。",
                        imageAssetName: "guide_home_header",
                        placeholderPrompt: "預留畫面：首頁頂部看病準備與中間電量、發作時間卡片"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "照護者看到的貼心首頁",
                        description: "如果您是照護者，中間區塊會貼心顯示「被照護長輩的姓名」，讓您隨時確認目前正在關心哪一位家人的日常動態。",
                        imageAssetName: "guide_home_caregiver",
                        placeholderPrompt: "預留畫面：照護者視角首頁，顯示被照護者姓名"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "查看今日服藥進度",
                        description: "首頁下方會列出今日需要服用的藥物（最多顯示 5 筆），點擊即可快速跳轉至用藥紀錄完成打卡。",
                        imageAssetName: "guide_home_med_today",
                        placeholderPrompt: "預留畫面：首頁下方今日用藥清單"
                    )
                ]
            ),
            GuideTopic(
                title: "手套連線與鬆緊調整",
                summary: "輕鬆將手套與手機藍牙連線，並利用滑桿微調手套長度與抑震強度。",
                systemIcon: "hand.wave.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "將手套連上手機",
                        description: "若顯示「尚未連線」，點擊搜尋按鈕便會尋找並連接您的手套。若手機藍牙尚未打開，畫面會提醒您已關閉，並引導您到手機設定中開啟藍牙。",
                        imageAssetName: "guide_glove_connect",
                        placeholderPrompt: "預留畫面：手套連線搜尋中與藍牙開啟指引提示"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "查看手套狀態與微調強度",
                        description: "連線後能看見目前手套電量與馬達是否正在運作。透過畫面中的強度滑桿，您可以輕鬆微調手套長度與運作強度，找到最舒服的配戴感。",
                        imageAssetName: "guide_glove_slider",
                        placeholderPrompt: "預留畫面：手套已連線狀態、電量與強度滑桿調整介面"
                    )
                ]
            )
        ],

        .tremor: [
            GuideTopic(
                title: "看懂震動強度圖表（標準模式）",
                summary: "用圖表清楚看見震動大小與發作時間點，還能左右滑動與放大查看。",
                systemIcon: "waveform.path.ecg",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "查看即時震動速度與強度",
                        description: "畫面上方會顯示目前手部震動速度與強度。如果對名詞不熟悉，點擊右上角的小問號就能看見親切的生活化說明。",
                        imageAssetName: "guide_tremor_metrics",
                        placeholderPrompt: "預留畫面：上方震動速度與震動強度卡片與問號圖示"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "查看震動圖表中的橘點與紅點",
                        description: "圖表中標示的橘色圓點代表手部震顫較明顯的時間。用手指點一下橘點會變成紅點，下方會自動幫您跳轉到該次事件，讓您記錄當下在做什麼。",
                        imageAssetName: "guide_tremor_dots",
                        placeholderPrompt: "預留畫面：圖表中橘點與紅點的標記提示"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "自由拖拉與縮放圖表",
                        description: "您可以像看照片一樣，用雙指放大縮小圖表，或是左右滑動瀏覽不同時段的震動狀況。",
                        imageAssetName: "guide_tremor_gesture",
                        placeholderPrompt: "預留畫面：雙指縮放與拖曳手勢指引圖"
                    )
                ]
            ),
            GuideTopic(
                title: "記錄手抖事件與上傳照片影片",
                summary: "記錄手抖當下正在做什麼，拍下照片或影片，回診時方便向醫師說明。",
                systemIcon: "tag.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "選擇當下活動與上傳影音",
                        description: "點開高震顫事件卡片，記錄您當下是在「吃飯、喝水」還是「寫字、走路」。您也可以上傳照片或影片，上傳後會像相簿輪播一樣方便翻閱。",
                        imageAssetName: "guide_event_edit",
                        placeholderPrompt: "預留畫面：展開事件卡片填寫活動標籤與拍照上傳"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "隨時修改或取消內容",
                        description: "儲存後的紀錄會鎖定保護。若想補充，點擊「編輯」即可修改；如果只是不小心點到，按下「取消」就能恢復原本的樣子。",
                        imageAssetName: "guide_event_save",
                        placeholderPrompt: "預留畫面：事件卡片編輯與取消按鈕"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "檢視當下抖動頻率圖",
                        description: "在事件卡片最下方，除了震動強度外，還有一張抖動頻率分佈圖，提供專業醫師精確分析是屬於哪一種晃動節奏。",
                        imageAssetName: "guide_event_freq_chart",
                        placeholderPrompt: "預留畫面：卡片下方的抖動頻率（Hz）分佈圖表"
                    )
                ]
            ),
            GuideTopic(
                title: "長輩友善：簡易模式",
                summary: "拿掉複雜圖表、字體放大，用最直覺的顏色告訴您目前手套狀態。",
                systemIcon: "eyeglasses",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "一鍵切換簡易模式",
                        description: "點選右上角的「簡易模式」，複雜的折線圖和數字圖表會自動隱藏，變成清楚的大字體與手套連線狀態，問號說明也更通俗易懂。",
                        imageAssetName: "guide_simple_mode_view",
                        placeholderPrompt: "預留畫面：大字體的簡易模式介面"
                    )
                ]
            )
        ],

        .moodBoard: [
            GuideTopic(
                title: "瀏覽家人溫暖留言",
                summary: "透過日期翻閱彼此的留言，隨時手動重新整理，傳遞家庭關心。",
                systemIcon: "note.text",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "挑選日期與手動整理",
                        description: "最上方可選擇想查看哪一天的留言。右上角有重新整理按鈕，想確認家人有沒有留下新關心，點一下就能即時更新。",
                        imageAssetName: "guide_mood_date_refresh",
                        placeholderPrompt: "預留畫面：頂部日期選擇器與重新整理按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "便利貼內容與專屬標記",
                        description: "每張便利貼左上角有心情圖案、左下角有發布者名字、右下角則是發送時間。若是家人之間個別叮嚀並設定「限照護者查看」，病患端不會顯示該張便利貼，給予照護者討論長輩照顧時的私密空間。",
                        imageAssetName: "guide_mood_cards",
                        placeholderPrompt: "預留畫面：彩色的便利貼看板與限照護者查看標記"
                    )
                ]
            ),
            GuideTopic(
                title: "寫一張心情便利貼",
                summary: "可以用打字或語音說話，挑選今天的心情或是喜歡的便利貼顏色。",
                systemIcon: "square.and.pencil",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "說話或打字輸入（最多100字）",
                        description: "點擊寫便利貼，在框格內寫下想對家人說的話（最多 100 字）。如果手指不方便打字，也可以跟著畫面提示使用手機上鍵盤內建的語音直接說話輸入。",
                        imageAssetName: "guide_write_note_voice",
                        placeholderPrompt: "預留畫面：文字輸入框與語音輸入按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "記錄心情或留下專屬叮嚀",
                        description: "如果您是病患，您可以只選心情、只打文字，或者兩者都填，沒有負擔。如果您是照護者，可選擇是否開啟「僅為照護者可查看」。最後挑選喜歡的便利貼底色即可送出！",
                        imageAssetName: "guide_write_note_color",
                        placeholderPrompt: "預留畫面：心情選擇、照護者限定開關與底色挑選盤"
                    )
                ]
            )
        ],

        .medication: [
            GuideTopic(
                title: "建立處方用藥清單",
                summary: "設定吃藥時間、一日多次服藥，以及自訂每週或每月的吃藥週期。",
                systemIcon: "list.clipboard.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "新增與管理藥品清單",
                        description: "在用藥頁點選「管理清單」，可以新增您每天服用的藥品。一種藥物可以設定早、中、晚等多個服藥時間點，也能設定特定週期（例如每天、每週幾或隔幾天吃一次）。",
                        imageAssetName: "guide_med_plan_create",
                        placeholderPrompt: "預留畫面：新增藥品表單與多時間點新增按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "貼片提醒設定",
                        description: "若您使用的是藥物貼片，系統會在清單中提醒您 14 天內曾使用貼片部位，但不會先限制黏貼位置，讓您在撕下換藥時再根據膚況彈性決定。",
                        imageAssetName: "guide_patch_reminder",
                        placeholderPrompt: "預留畫面：貼片用藥提醒開關"
                    )
                ]
            ),
            GuideTopic(
                title: "貼片換藥與 30 秒按壓指引",
                summary: "提醒撕除舊貼片、記錄黏貼部位與皮膚狀況，並貼心引導按壓 30 秒吸收。",
                systemIcon: "bandage.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "確認撕除舊貼片與選擇部位",
                        description: "換貼片時點進貼片紀錄，系統第一步會提醒您「是否已撕除舊貼片」。接著勾選這次貼上的身體部位（如手臂、腹部、大腿等），並記錄皮膚狀況，必要時可拍照存證。",
                        imageAssetName: "guide_patch_step1",
                        placeholderPrompt: "預留畫面：撕除舊貼片核取方塊與身體部位勾選"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "30 秒按壓手掌倒數計時",
                        description: "貼好送出後，畫面會跳出「30 秒按壓倒數」，引導您用溫熱的手掌緊壓貼片以助藥物吸收。若您已經按壓好，也可以直接點選跳過。",
                        imageAssetName: "guide_patch_timer",
                        placeholderPrompt: "預留畫面：30 秒手掌按壓倒計時彈窗"
                    )
                ]
            ),
            GuideTopic(
                title: "服藥打卡與各項生活紀錄",
                summary: "勾選完成吃藥、補記臨時用藥，還能記錄血壓血糖與突發症狀。",
                systemIcon: "square.and.pencil.circle.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "每日服藥輕鬆勾選",
                        description: "在「用藥清單」中，吃完藥只要輕輕打勾，系統就會自動將它存入「服藥紀錄」中。如果要補記醫生臨時加開的藥，也可以在服藥紀錄中手動單次新增。",
                        imageAssetName: "guide_med_check_done",
                        placeholderPrompt: "預留畫面：今日用藥清單勾選完成畫面"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "左滑修改與刪除紀錄",
                        description: "在實際服藥紀錄中，手指輕輕向左滑動任何一筆紀錄，就能重新修改時間劑量，或是直接刪除不小心的重複打卡。",
                        imageAssetName: "guide_med_swipe_edit",
                        placeholderPrompt: "預留畫面：紀錄項目向左滑動顯示編輯與刪除按鈕"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "生理健康與表徵照片牆",
                        description: "在「生理健康」分頁可隨手記錄血壓、血糖、體溫與睡眠。在「表徵記錄」分頁則能寫下突發的身體僵硬或不適，並拍照（最多 5 張）存入生活記錄牆。",
                        imageAssetName: "guide_health_vitals_symptoms",
                        placeholderPrompt: "預留畫面：生理數據填寫表單與症狀照片牆"
                    ),
                    GuideStep(
                        stepNumber: 4,
                        title: "觀察藥效發揮情況",
                        description: "切換到「藥效波動」分頁，圖表中會標註您吃藥的時間點，方便您與家人清楚對照吃藥前後手部抖動有沒有減緩。",
                        imageAssetName: "guide_med_effect_chart",
                        placeholderPrompt: "預留畫面：結合服藥時間點的震動波動圖"
                    )
                ]
            )
        ],

        .healthAndAssessment: [
            GuideTopic(
                title: "每日自我健康評估",
                summary: "三種填寫模式隨心選，做完自動結算分數並取消當天的提醒通知。",
                systemIcon: "checklist",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "依當下時間挑選填寫模式",
                        description: "評估表提供三種模式：(1) 1 分鐘快速檢測：日常精神累時快速答題打卡；(2) 主題分類檢測：單獨查看「心情」、「日常自理」或「手腳動作」；(3) 完整 25 題每週量表：每週定期詳細評估長期身體變化。",
                        imageAssetName: "guide_assessment_types",
                        placeholderPrompt: "預留畫面：三種評估模式選擇清單"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "自動計算得分與提醒銷除",
                        description: "填完送出後，系統會自動加總分數並儲存。同時，系統會貼心地為您關閉今天「填寫評估」的提醒通知，日曆上也會標記已完成打卡。",
                        imageAssetName: "guide_assessment_score",
                        placeholderPrompt: "預留畫面：測驗完成分數卡片與日曆完成標記"
                    )
                ]
            )
        ],

        .reminderAndReport: [
            GuideTopic(
                title: "設定生活推播提醒",
                summary: "吃藥、回診、慢箋領藥與手抖忘記備註，手機都會準時溫馨提醒。",
                systemIcon: "bell.badge.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "自訂需要的提醒事項",
                        description: "在提醒設定中，您可以針對「吃藥提醒」、「回診提醒（如看診前 1 天或當天早上）」、「領藥提醒」與「高震顫事件未標記提醒」分別開啟或關閉，並自由調整您習慣被提醒的時間。",
                        imageAssetName: "guide_reminders_overview",
                        placeholderPrompt: "預留畫面：各類生活提醒開關與時間設定選單"
                    )
                ]
            ),
            GuideTopic(
                title: "匯出門診就醫資料（產生 PDF 報告）",
                summary: "整理最近一週或整個月的身體紀錄，由 AI 幫忙彙整重點，列印或分享給醫師看。",
                systemIcon: "doc.text.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "選擇匯出時間與報告內容",
                        description: "設定要整理的日期區間，勾選想要放進報告裡的項目。其中「看病前準備」產出後還會顯示在 App 首頁最上方，方便您到診間時隨時查閱。",
                        imageAssetName: "guide_export_step1_view",
                        placeholderPrompt: "預留畫面：選擇匯出日期區間與報告項目勾選"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "讓 AI 幫您整理諮詢重點",
                        description: "若需要 AI 摘要，點擊下一步，您可以決定是否參考平日的心情留言，並勾選想請教醫師的主題。點擊「產生摘要」後，AI 寫出來的重點您也可以親自手動修改文字。",
                        imageAssetName: "guide_export_step2_ai",
                        placeholderPrompt: "預留畫面：AI 摘要產生與手動編輯文字框"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "預覽並儲存為 PDF 報告",
                        description: "按下預覽按鈕，就能看到整齊精美的報告，裡面有您的姓名、發作頻率圖、高震顫紀錄、日常用藥與健康數據。您可以直接存成檔案傳給醫師或透過印表機列印成紙本。",
                        imageAssetName: "guide_pdf_preview_screen",
                        placeholderPrompt: "預留畫面：完整就診 PDF 報告預覽畫面與分享按鈕"
                    )
                ]
            )
        ],

        .familyShare: [
            GuideTopic(
                title: "家人帳號配對與管理",
                summary: "病患產出配對碼給家人輸入，互相關心日常，隨時可解除連結。",
                systemIcon: "person.2.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "病患產出號碼，家人輸入連結",
                        description: "病患在「家屬設定」中點擊產生一組專屬號碼給家人；家人只要在自己的手機中輸入這組號碼，就能成功互相連動。",
                        imageAssetName: "guide_family_code_gen",
                        placeholderPrompt: "預留畫面：病患產生專屬連動碼與家屬輸入畫面"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "家屬名單互通與解除綁定",
                        description: "一位病患可以連動多位家人。連動後，所有人都能看見彼此的名字與信箱。照護者一次只能連動一位病患（需先解除才能連下一位）；病患端則不限數量，也可以隨時把不再連動的家屬解除連結。",
                        imageAssetName: "guide_family_members_list",
                        placeholderPrompt: "預留畫面：已連線家人名單與解除連動按鈕"
                    )
                ]
            )
        ],

        .aiAssistant: [
            GuideTopic(
                title: "與 AI 健康助手聊聊天",
                summary: "隨時解答長輩生活照護疑問，支援文字與日期搜尋，閱讀輕鬆無壓力。",
                systemIcon: "sparkles",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "隨時發問生活衛教問題",
                        description: "在對話框內像跟朋友聊天一樣說出您的疑惑（例如：忘記吃藥怎麼辦、貼片起疹子怎麼處理）。小助手會整理出好閱讀的重點給您。如果不想等它說完，隨時可以按「中止」按鈕中斷回答。",
                        imageAssetName: "guide_ai_chat_talk",
                        placeholderPrompt: "預留畫面：AI 諮詢對話框與中止按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "用文字或日期找回聊過的事",
                        description: "上方有搜尋欄，打入關鍵字或挑選特定日期，就能直接跳回那天聊過的對話紀錄，方便隨時複習衛教建議。",
                        imageAssetName: "guide_ai_chat_search",
                        placeholderPrompt: "預留畫面：AI 聊天室搜尋工具列與日曆篩選"
                    )
                ]
            )
        ]
    ]
}

struct GuideImagePlaceholder: View {
    let assetName: String?
    let prompt: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            if let name = assetName, let uiImage = UIImage(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26))
                        .foregroundColor(AppTheme.primary(for: colorScheme))

                    Text("畫面操作指引圖示")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
                .background(AppTheme.background(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.3))
                )
                .cornerRadius(12)
            }
        }
        .padding(.vertical, 4)
    }
}

struct UserGuideView: View {
    @State private var selectedCategory: GuideCategory = .all
    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var filteredTopics: [(category: GuideCategory, topic: GuideTopic)] {
        var results: [(category: GuideCategory, topic: GuideTopic)] = []

        let categoriesToSearch: [GuideCategory] = (selectedCategory == .all)
            ? GuideCategory.allCases.filter { $0 != .all }
            : [selectedCategory]

        for category in categoriesToSearch {
            if let topics = GuideRepository.topics[category] {
                for topic in topics {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        results.append((category, topic))
                    } else {
                        let query = searchText.lowercased()
                        let matchTitle = topic.title.lowercased().contains(query)
                        let matchSummary = topic.summary.lowercased().contains(query)
                        let matchSteps = topic.steps.contains {
                            $0.title.lowercased().contains(query) || $0.description.lowercased().contains(query)
                        }

                        if matchTitle || matchSummary || matchSteps {
                            results.append((category, topic))
                        }
                    }
                }
            }
        }
        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilterBar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredTopics.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(filteredTopics, id: \.topic.id) { pair in
                                NavigationLink(destination: GuideDetailView(topic: pair.topic)) {
                                    GuideTopicCard(topic: pair.topic, category: pair.category)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("系統操作說明")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜尋使用方法（如：貼片、配對、自評）")
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuideCategory.allCases) { category in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 11))
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: selectedCategory == category ? .bold : .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedCategory == category ? AppTheme.primary(for: colorScheme) : AppTheme.cardBackground(for: colorScheme))
                        .foregroundColor(selectedCategory == category ? .white : AppTheme.textSecondary(for: colorScheme))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedCategory == category ? Color.clear : AppTheme.textSecondary(for: colorScheme).opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppTheme.cardBackground(for: colorScheme))
        .overlay(Divider(), alignment: .bottom)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.top, 40)

            Text("找不到符合的說明主題")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("請嘗試輸入其他生活關鍵字，或切換上方分類檢視。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

struct GuideTopicCard: View {
    let topic: GuideTopic
    let category: GuideCategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.primary(for: colorScheme).opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: topic.systemIcon)
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(topic.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.4))
                }

                Text(topic.summary)
                    .font(.system(size: 12.5))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(2)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    Text(category.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                        .cornerRadius(4)

                    Text("共 \(topic.steps.count) 個步驟")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
                }
                .padding(.top, 3)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.textSecondary(for: colorScheme).opacity(0.15), lineWidth: 1)
        )
    }
}

struct GuideDetailView: View {
    let topic: GuideTopic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))

                    Text(topic.summary)
                        .font(.system(size: 13.5))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(3)
                }
                .padding(.bottom, 4)

                Divider()

                ForEach(topic.steps) { step in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.primary(for: colorScheme))
                                    .frame(width: 24, height: 24)

                                Text("\(step.stepNumber)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            Text(step.title)
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text(step.description)
                            .font(.system(size: 13.5))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineSpacing(4)
                            .padding(.leading, 34)

                        GuideImagePlaceholder(
                            assetName: step.imageAssetName,
                            prompt: step.placeholderPrompt
                        )
                        .padding(.leading, 34)
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("操作指引")
        .navigationBarTitleDisplayMode(.inline)
    }
}
