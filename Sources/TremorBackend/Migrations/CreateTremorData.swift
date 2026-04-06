import Fluent

struct CreateTremorData: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("tremor_data")
            .id()
            .field("user_id", .int, .required)
            .field("timestamp", .datetime)
            .field("acc_x", .double, .required)
            .field("acc_y", .double, .required)
            .field("acc_z", .double, .required)
            .field("gyro_x", .double, .required)
            .field("gyro_y", .double, .required)
            .field("gyro_z", .double, .required)
            .field("tremor_frequency", .double)
            .field("amplitude", .double)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("tremor_data").delete()
    }
}
