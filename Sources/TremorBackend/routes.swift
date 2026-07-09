import Fluent
import Vapor

func routes(_ app: Application) throws {
    // 註冊 Controller
    try app.register(collection: UserController())
    // 使用 JWT 中介軟體保護 tremor 路由
    let protected = app.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())
    try protected.register(collection: TremorController())
    try protected.register(collection: MedicationController()) 
}
