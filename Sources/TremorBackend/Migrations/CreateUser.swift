import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            // 關鍵：這行會告訴資料庫 id 是主鍵且會自動跳號
            .field("id", .int, .identifier(autoIncrement: true))
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("name", .string)
            .field("birth", .date)
            .field("gender", .int)
            .field("disease_stage", .string)
            .unique(on: "email")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
    }
}
