import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .id() // 預設使用 UUID，但如果你 Model 用 Int，建議改為 .field("id", .int, .identifier(autoIncrement: true))
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("name", .string)
            .field("birth", .date)
            .field("gender", .int)
            .field("disease_stage", .string)
            .unique(on: "email") // 確保 Email 不重複
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
    }
}
