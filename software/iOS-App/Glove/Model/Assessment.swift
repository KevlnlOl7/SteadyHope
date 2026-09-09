import SwiftUI

enum AssessmentSection: String, CaseIterable, Identifiable {
    case mood = "心情與思考"
    case adl = "日常生活能力"
    case motor = "動作能力自測"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mood: return "brain.head.profile"
        case .adl: return "figure.walk"
        case .motor: return "hand.tap.fill"
        }
    }
}

/// 每日評估表題目選項
struct AssessmentOption: Identifiable {
    let id = UUID()

    /// 該選項對應之量表得分
    let score: Int

    /// 選項簡短標題
    let title: String

    /// 選項詳細情境描述
    let description: String
}

/// 每日評估表題目
struct AssessmentQuestion: Identifiable {
    /// 題目編號識別碼
    let id: Int

    /// 題目所屬的評估分類面向
    let section: AssessmentSection

    /// 題目主標題
    let title: String

    /// 題目引導副標題或操作提示
    let subtitle: String

    /// 該題目所屬之選項陣列
    let options: [AssessmentOption]
}

/// 每日評估表題庫
struct AssessmentBank {
    /// 評估問卷完整題目集合清單
    static let questions: [AssessmentQuestion] = [
        // 第一部分：心情與思考狀況
        AssessmentQuestion(
            id: 1, section: .mood, title: "記憶與思考", subtitle: "今日的記憶與思考狀況",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "無明顯異常"),
                AssessmentOption(score: 1, title: "輕微", description: "常忘事，但想一下能想起來"),
                AssessmentOption(score: 2, title: "中度", description: "處理複雜事情有困難，生活偶爾需要提示"),
                AssessmentOption(score: 3, title: "重度", description: "時間地點容易搞混，處理事情有重度困難"),
                AssessmentOption(score: 4, title: "極嚴重", description: "嚴重失憶，無法解決問題，無法獨立生活")
            ]
        ),
        AssessmentQuestion(
            id: 2, section: .mood, title: "精神狀況", subtitle: "今日的精神狀況或幻覺體驗",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "無異常"),
                AssessmentOption(score: 1, title: "輕微", description: "做很鮮明的夢"),
                AssessmentOption(score: 2, title: "良性幻覺", description: "看到或聽到不真實畫面，但自己知道是假的"),
                AssessmentOption(score: 3, title: "中度", description: "看到或聽到假的且信以為真，日常生活受干擾"),
                AssessmentOption(score: 4, title: "重度", description: "持續性幻覺或妄想，無法照顧自己")
            ]
        ),
        AssessmentQuestion(
            id: 3, section: .mood, title: "情緒（沮喪）", subtitle: "今日的情緒與心情狀態",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "心情穩定"),
                AssessmentOption(score: 1, title: "輕微", description: "偶爾悲傷或自責，但只持續一下子"),
                AssessmentOption(score: 2, title: "中度", description: "持續心情低落（持續一週以上）"),
                AssessmentOption(score: 3, title: "重度", description: "心情低落且伴隨活動力減退（如失眠、厭食、喪失樂趣）"),
                AssessmentOption(score: 4, title: "極嚴重", description: "持續低落且有自殺念頭或行動")
            ]
        ),
        AssessmentQuestion(
            id: 4, section: .mood, title: "活動意願（動機）", subtitle: "今日的主動性與動機",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "動機良好"),
                AssessmentOption(score: 1, title: "輕微", description: "比平常被動，不如以往積極"),
                AssessmentOption(score: 2, title: "中度", description: "對非例行或需要選擇的活動缺乏主動與興趣"),
                AssessmentOption(score: 3, title: "重度", description: "對日常例行活動缺乏主動與興趣"),
                AssessmentOption(score: 4, title: "極嚴重", description: "完全喪失動機、退縮")
            ]
        ),

        // 第二部分：日常生活能力
        AssessmentQuestion(
            id: 5, section: .adl, title: "講話溝通", subtitle: "今日的言語表達與溝通",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "表達流暢"),
                AssessmentOption(score: 1, title: "輕微影響", description: "但別人仍聽得懂"),
                AssessmentOption(score: 2, title: "中度影響", description: "有時需要重新講一遍"),
                AssessmentOption(score: 3, title: "重度影響", description: "經常需要重新講一遍"),
                AssessmentOption(score: 4, title: "極嚴重", description: "大半無法讓人瞭解")
            ]
        ),
        AssessmentQuestion(
            id: 6, section: .adl, title: "口水控制", subtitle: "今日的唾液分泌狀況",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "無異常"),
                AssessmentOption(score: 1, title: "輕微", description: "少許過量唾液，晚上睡覺可能會流出來"),
                AssessmentOption(score: 2, title: "中度", description: "唾液過量顯著"),
                AssessmentOption(score: 3, title: "重度", description: "嚴重口水過多"),
                AssessmentOption(score: 4, title: "極嚴重", description: "嚴重垂涎，一直需要紙巾擦拭")
            ]
        ),
        AssessmentQuestion(
            id: 7, section: .adl, title: "吞嚥飲食", subtitle: "今日進食時的吞嚥狀況",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "吞嚥順暢"),
                AssessmentOption(score: 1, title: "輕微", description: "很少嗆到或哽住"),
                AssessmentOption(score: 2, title: "中度", description: "偶爾會嗆到或哽住"),
                AssessmentOption(score: 3, title: "重度", description: "需要進食半流質食物"),
                AssessmentOption(score: 4, title: "極嚴重", description: "需插鼻胃管或胃造口")
            ]
        ),
        AssessmentQuestion(
            id: 8, section: .adl, title: "寫字", subtitle: "今日寫字順暢度與字跡",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "書寫正常"),
                AssessmentOption(score: 1, title: "輕微", description: "寫字有點慢或字體偏小"),
                AssessmentOption(score: 2, title: "中度", description: "寫字慢或字體小，但別人還可辨認"),
                AssessmentOption(score: 3, title: "重度", description: "嚴重遲緩，無法辨認所有字體"),
                AssessmentOption(score: 4, title: "極嚴重", description: "大部分字體完全無法辨認")
            ]
        ),
        AssessmentQuestion(
            id: 9, section: .adl, title: "用餐進食", subtitle: "今日自行進食的能力",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "可自行順利進食"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢笨拙，但不需要幫忙"),
                AssessmentOption(score: 2, title: "中度", description: "有點緩慢笨拙，可以使用筷子，有時需要幫忙"),
                AssessmentOption(score: 3, title: "重度", description: "必須使用湯匙進食，自己可緩慢吃"),
                AssessmentOption(score: 4, title: "極嚴重", description: "完全需要別人餵食")
            ]
        ),
        AssessmentQuestion(
            id: 10, section: .adl, title: "穿衣服", subtitle: "今日穿脫衣服的能力",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "獨立穿脫"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢，但不需要幫忙"),
                AssessmentOption(score: 2, title: "中度", description: "有時需要幫忙扣釦子或穿袖子"),
                AssessmentOption(score: 3, title: "重度", description: "需要更多幫助，但部分可獨自完成"),
                AssessmentOption(score: 4, title: "極嚴重", description: "完全需要別人幫忙")
            ]
        ),
        AssessmentQuestion(
            id: 11, section: .adl, title: "個人衛生", subtitle: "今日盥洗與清潔的能力",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "獨立盥洗"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢，但不需要幫忙"),
                AssessmentOption(score: 2, title: "中度", description: "洗澡需要幫忙，個人衛生處理緩慢"),
                AssessmentOption(score: 3, title: "重度", description: "盥洗、刷牙、梳頭、上廁所都需要幫助"),
                AssessmentOption(score: 4, title: "極嚴重", description: "需要導尿管或其他器具協助")
            ]
        ),
        AssessmentQuestion(
            id: 12, section: .adl, title: "床上翻身", subtitle: "今日在床上翻身或拉被子的能力",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "翻身順暢"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢，但不需要幫忙"),
                AssessmentOption(score: 2, title: "中度", description: "可自己翻身或調整被單，但很費力"),
                AssessmentOption(score: 3, title: "重度", description: "想翻身但無法靠自己力量翻身或拉被單"),
                AssessmentOption(score: 4, title: "極嚴重", description: "完全沒辦法自己做")
            ]
        ),
        AssessmentQuestion(
            id: 13, section: .adl, title: "跌倒狀況", subtitle: "今日跌倒的頻率（與走路凍僵無關）",
            options: [
                AssessmentOption(score: 0, title: "無跌倒", description: "今日未跌倒"),
                AssessmentOption(score: 1, title: "極少跌倒", description: "極少發生"),
                AssessmentOption(score: 2, title: "偶爾跌倒", description: "一天少於 1 次"),
                AssessmentOption(score: 3, title: "中度", description: "平均一天跌倒 1 次"),
                AssessmentOption(score: 4, title: "重度", description: "一天跌倒超過 1 次")
            ]
        ),
        AssessmentQuestion(
            id: 14, section: .adl, title: "走路凍僵", subtitle: "今日走路時出現腳卡住（凍僵）的狀況",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "無凍僵現象"),
                AssessmentOption(score: 1, title: "輕微", description: "很少凍僵，起步時有點躊躇"),
                AssessmentOption(score: 2, title: "中度", description: "走路時有時候會凍僵"),
                AssessmentOption(score: 3, title: "重度", description: "常常凍僵，有時會因此跌倒"),
                AssessmentOption(score: 4, title: "極嚴重", description: "常常因為凍僵而跌倒")
            ]
        ),
        AssessmentQuestion(
            id: 15, section: .adl, title: "步行能力", subtitle: "今日整體走路狀況",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "步態平穩"),
                AssessmentOption(score: 1, title: "輕微困難", description: "可能不擺動手臂或拖著腳走"),
                AssessmentOption(score: 2, title: "中度困難", description: "需要一點點扶持或協助（或不需要）"),
                AssessmentOption(score: 3, title: "重度", description: "嚴重影響走路"),
                AssessmentOption(score: 4, title: "極嚴重", description: "即使有人扶也無法走路")
            ]
        ),
        AssessmentQuestion(
            id: 16, section: .adl, title: "顫抖感受", subtitle: "今日自覺顫抖對生活的干擾",
            options: [
                AssessmentOption(score: 0, title: "無顫抖", description: "無明顯顫抖"),
                AssessmentOption(score: 1, title: "輕微", description: "很少出現且不造成困擾"),
                AssessmentOption(score: 2, title: "中度", description: "造成一些困擾"),
                AssessmentOption(score: 3, title: "重度", description: "許多日常活動受干擾"),
                AssessmentOption(score: 4, title: "極嚴重", description: "大部分日常活動受干擾")
            ]
        ),
        AssessmentQuestion(
            id: 17, section: .adl, title: "異常感覺", subtitle: "今日身體異常感覺（如肢體麻木、刺痛、疼痛）",
            options: [
                AssessmentOption(score: 0, title: "無異常", description: "無不適感"),
                AssessmentOption(score: 1, title: "輕微", description: "偶爾四肢麻木、刺痛或輕微疼痛"),
                AssessmentOption(score: 2, title: "中度", description: "經常麻木、刺痛、輕微疼痛，但不致於煩惱"),
                AssessmentOption(score: 3, title: "重度", description: "常感到疼痛"),
                AssessmentOption(score: 4, title: "極嚴重", description: "非常疼痛")
            ]
        ),

        // 第三部分：動作能力自測
        AssessmentQuestion(
            id: 18, section: .motor, title: "手指打拍", subtitle: "大拇指與食指盡量張開，以最快速度打拍 5 秒",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "5 秒 15 下以上"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢且幅度減少（5 秒 11-14 下）"),
                AssessmentOption(score: 2, title: "中度障礙", description: "容易疲勞，動作有時中斷（5 秒 7-10 下）"),
                AssessmentOption(score: 3, title: "重度障礙", description: "啟動很慢，動作經常中斷（5 秒 3-6 下）"),
                AssessmentOption(score: 4, title: "極嚴重", description: "幾乎無法動作（5 秒 0-2 下）")
            ]
        ),
        AssessmentQuestion(
            id: 19, section: .motor, title: "手掌握合", subtitle: "手掌盡量張開後再快速握拳，連續測試 5 秒",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "動作流暢"),
                AssessmentOption(score: 1, title: "輕微", description: "有點緩慢或張開幅度稍小"),
                AssessmentOption(score: 2, title: "中度障礙", description: "容易疲勞，動作有時中斷"),
                AssessmentOption(score: 3, title: "重度障礙", description: "開始很吃力，動作經常中斷"),
                AssessmentOption(score: 4, title: "極嚴重", description: "幾乎無法動作")
            ]
        ),
        AssessmentQuestion(
            id: 20, section: .motor, title: "前臂轉動", subtitle: "手臂向前伸手掌快速做內旋與外轉動作，測試 5 秒",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "轉動幅度大且流暢"),
                AssessmentOption(score: 1, title: "輕微", description: "有點遲緩，旋轉幅度稍小"),
                AssessmentOption(score: 2, title: "中度遲緩", description: "容易疲勞，動作有時中斷"),
                AssessmentOption(score: 3, title: "重度遲緩", description: "開始很吃力，動作經常中斷"),
                AssessmentOption(score: 4, title: "極嚴重", description: "幾乎無法動作")
            ]
        ),
        AssessmentQuestion(
            id: 21, section: .motor, title: "兩腳靈敏度", subtitle: "腳跟抬高約 8 公分，以最快速度連續拍打地面 5 秒",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "拍打節奏流暢"),
                AssessmentOption(score: 1, title: "輕微", description: "有點遲緩，抬腳幅度稍小"),
                AssessmentOption(score: 2, title: "中度遲緩", description: "容易疲勞，動作有時中斷"),
                AssessmentOption(score: 3, title: "重度遲緩", description: "開始很吃力，動作經常中斷"),
                AssessmentOption(score: 4, title: "極嚴重", description: "幾乎無法動作")
            ]
        ),
        AssessmentQuestion(
            id: 22, section: .motor, title: "從椅子站起", subtitle: "雙手抱胸，從有靠背的椅子站起來",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "輕鬆站起"),
                AssessmentOption(score: 1, title: "輕微", description: "遲緩或需要試好幾次"),
                AssessmentOption(score: 2, title: "中度", description: "需要用手推扶手或膝蓋才能站起來"),
                AssessmentOption(score: 3, title: "重度", description: "容易向後跌回，需試多次但仍可自己站起"),
                AssessmentOption(score: 4, title: "極嚴重", description: "必須靠別人幫忙才能站起來")
            ]
        ),
        AssessmentQuestion(
            id: 23, section: .motor, title: "站立姿勢", subtitle: "站立時的身體姿態",
            options: [
                AssessmentOption(score: 0, title: "正常挺直", description: "姿態良好"),
                AssessmentOption(score: 1, title: "輕微", description: "不是很挺，稍微駝背"),
                AssessmentOption(score: 2, title: "中度駝背", description: "明顯異常，有輕微側彎"),
                AssessmentOption(score: 3, title: "重度駝背", description: "身體中度側彎"),
                AssessmentOption(score: 4, title: "極嚴重", description: "身體嚴重向前傾斜彎曲")
            ]
        ),
        AssessmentQuestion(
            id: 24, section: .motor, title: "走路步態", subtitle: "走路時的步伐型態",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "步態流暢"),
                AssessmentOption(score: 1, title: "輕微", description: "步態遲緩、拖步，但不會越走越急"),
                AssessmentOption(score: 2, title: "中度", description: "走路困難，步伐急促、碎步或向前衝"),
                AssessmentOption(score: 3, title: "重度", description: "走路極度困難，需要別人扶持"),
                AssessmentOption(score: 4, title: "極嚴重", description: "即使有人扶也無法走路")
            ]
        ),
        AssessmentQuestion(
            id: 25, section: .motor, title: "全身動作遲緩", subtitle: "今日全身整體的動作敏捷度",
            options: [
                AssessmentOption(score: 0, title: "正常", description: "動作敏捷"),
                AssessmentOption(score: 1, title: "輕微", description: "動作稍微變慢，給人小心翼翼的感覺，幅度可能微減"),
                AssessmentOption(score: 2, title: "中度輕微", description: "動作確定變慢或減少，幅度稍微減小"),
                AssessmentOption(score: 3, title: "中度", description: "動作明顯變慢或減少，幅度減小"),
                AssessmentOption(score: 4, title: "重度", description: "嚴重變慢或動作極少")
            ]
        )
    ]
}
