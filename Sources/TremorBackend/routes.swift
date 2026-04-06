import Fluent
import Vapor

func routes(_ app: Application) throws {
    // 註冊 Controller
    try app.register(collection: UserController())
    try app.register(collection: TremorController())
}
