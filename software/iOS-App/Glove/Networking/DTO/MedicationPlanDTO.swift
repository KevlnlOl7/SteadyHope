import Foundation

/// 負責處理用藥計畫與後端 API 對接之資料傳輸物件 (DTO)
struct MedicationPlanDTO: Codable {
    var id: Int?
    var userID: Int
    var name: String
    var dose: String
    var medType: MedicationType
    var defaultPatchRegion: PatchRegion?
    var timeSlotsRaw: String
    var startDate: Date
    var repeatFrequency: RepeatFrequency
    var customInterval: Int
    var customUnit: CustomRepeatUnit
    var weekdaysRaw: String
    var monthDaysRaw: String
    var creatorRole: Int?

    init(
        id: Int? = nil,
        userID: Int,
        name: String,
        dose: String,
        medType: MedicationType,
        defaultPatchRegion: PatchRegion? = nil,
        timeSlotsRaw: String,
        startDate: Date,
        repeatFrequency: RepeatFrequency,
        customInterval: Int,
        customUnit: CustomRepeatUnit,
        weekdaysRaw: String,
        monthDaysRaw: String,
        creatorRole: Int? = nil
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dose = dose
        self.medType = medType
        self.defaultPatchRegion = defaultPatchRegion
        self.timeSlotsRaw = timeSlotsRaw
        self.startDate = startDate
        self.repeatFrequency = repeatFrequency
        self.customInterval = customInterval
        self.customUnit = customUnit
        self.weekdaysRaw = weekdaysRaw
        self.monthDaysRaw = monthDaysRaw
        self.creatorRole = creatorRole
    }

    /// 從 JSON 解碼器初始化並處理空字串轉 nil 防呆
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(Int.self, forKey: .id)
        userID = try container.decode(Int.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        dose = try container.decode(String.self, forKey: .dose)
        medType = try container.decode(MedicationType.self, forKey: .medType)

        if let raw = try container.decodeIfPresent(String.self, forKey: .defaultPatchRegion)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            defaultPatchRegion = PatchRegion(rawValue: raw)
        } else {
            defaultPatchRegion = nil
        }

        timeSlotsRaw = try container.decode(String.self, forKey: .timeSlotsRaw)
        startDate = try container.decode(Date.self, forKey: .startDate)
        repeatFrequency = try container.decode(RepeatFrequency.self, forKey: .repeatFrequency)
        customInterval = try container.decode(Int.self, forKey: .customInterval)
        customUnit = try container.decode(CustomRepeatUnit.self, forKey: .customUnit)
        weekdaysRaw = try container.decode(String.self, forKey: .weekdaysRaw)
        monthDaysRaw = try container.decode(String.self, forKey: .monthDaysRaw)
        creatorRole = try container.decodeIfPresent(Int.self, forKey: .creatorRole)
    }

    /// 將 DTO 轉換為本機領域模型 MedicationPlan
    func toModel() -> MedicationPlan {
        MedicationPlan(
            id: id,
            userID: userID,
            name: name,
            dose: dose,
            medType: medType,
            defaultPatchRegion: defaultPatchRegion,
            timeSlotsRaw: timeSlotsRaw,
            startDate: startDate,
            repeatFrequency: repeatFrequency,
            customInterval: customInterval,
            customUnit: customUnit,
            weekdaysRaw: weekdaysRaw,
            monthDaysRaw: monthDaysRaw,
            creatorRole: creatorRole
        )
    }
}
