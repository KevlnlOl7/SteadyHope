import Foundation

/// 醫療報告匯出之預設配置與選單選項
struct ReportConfig {
    /// 第一頁提供選擇的報告彙整種類選項
    static let reportTypeOptions = [
        "看病前準備",
        "病人狀況描述",
        "上次回診差異",
        "其他科別用藥與特殊補充",
        "想問醫生的問題",
    ]

    /// 第二頁提供選擇的 13 大健康觀察主題清單
    static let defaultCategories: [CategoryItem] = [
        CategoryItem(
            title: "身體與動作狀況",
            description:
                "例如：小碎步、手抖、肌肉僵硬、平衡差、微寫症/字變小、日常精細動作困難（如扣鈕扣、剪指甲、插鑰匙）",
            icon: "figure.walk"
        ),
        CategoryItem(
            title: "用藥與特殊反應",
            description:
                "例如：藥效太快退（Wearing-off）、吃藥後異常扭動（異動症）、噁心或白天極度嗜睡等副作用",
            icon: "pills.fill"
        ),
        CategoryItem(
            title: "跌倒與安全事件",
            description:
                "例如：近期實質跌倒、差點摔倒、重心不穩、起步或轉彎時腳卡住（凍結步態）",
            icon: "exclamationmark.triangle.fill"
        ),
        CategoryItem(
            title: "睡眠與夜間作息",
            description:
                "例如：半夜大喊大叫、做噩夢拳打腳踢（REM睡眠異常）、失眠、日夜倒錯",
            icon: "moon.stars.fill"
        ),
        CategoryItem(
            title: "心情與情緒波動",
            description: "例如：莫名焦慮、情緒低落、提不起勁、易怒或情緒起伏劇烈",
            icon: "face.smiling.fill"
        ),
        CategoryItem(
            title: "記憶與精神認知",
            description: "例如：忘東忘西、精神恍惚、出現幻覺（看到不存在的人或動物）",
            icon: "brain.head.profile"
        ),
        CategoryItem(
            title: "飲食與吞嚥問題",
            description: "例如：喝水容易嗆到、流口水、吞嚥困難、用餐時間過長",
            icon: "cup.and.saucer.fill"
        ),
        CategoryItem(
            title: "語言與溝通狀況",
            description: "例如：說話聲音變小聲、口齒不清、講話卡住、社交退縮不願說話",
            icon: "waveform.and.mic"
        ),
        CategoryItem(
            title: "皮膚與感官異常",
            description:
                "例如：臉部嚴重出油、莫名暴汗、嗅覺喪失、複視/看東西有雙影、眼球轉動不靈活",
            icon: "eye.fill"
        ),
        CategoryItem(
            title: "體重與營養追蹤",
            description: "例如：體重莫名下降、胃口極差、整天沒有精神",
            icon: "scalemass.fill"
        ),
        CategoryItem(
            title: "排泄與自律神經",
            description:
                "例如：嚴重便秘、頻尿、夜尿次數多、起立時頭暈（姿勢性低血壓）",
            icon: "drop.fill"
        ),
        CategoryItem(
            title: "日常活動與輔具使用",
            description:
                "例如：日常翻身困難、穿衣或洗澡需人協助、助行器或拐杖使用狀況",
            icon: "figure.roll"
        ),
        CategoryItem(
            title: "照護環境與特殊事件",
            description:
                "例如：感冒生病、更換主要照顧者或看護、其他科別用藥變動或看診紀錄",
            icon: "house.fill"
        ),
        CategoryItem(
            title: "其他（自由補充）",
            description: "自由填寫任何想記錄的狀況、注意事項或相關補充說明",
            icon: "ellipsis.circle.fill"
        ),
    ]
}
