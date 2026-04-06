import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // 將路徑分群，所有這裏的路由都會以 /users 開頭
        let users = routes.grouped("users")
        users.post("register", use: register)
        users.post("login", use: login)
    }

    // 註冊邏輯
    @Sendable
    func register(req: Request) async throws -> UserResponse {
        struct RegisterRequest: Content {
            let email: String
            let password: String
            let name: String?
            let birth: Date?
            let gender: Int?
            let diseaseStage: String?
        }

        let data = try req.content.decode(RegisterRequest.self)
        // 使用非同步雜湊更安全且不阻塞
        let hash = try await req.password.async.hash(data.password)

        let user = User(
            email: data.email,
            passwordHash: hash,
            birth: data.birth,
            name: data.name,
            gender: data.gender,
            diseaseStage: data.diseaseStage
        )

        try await user.save(on: req.db)
        return user.toResponse() // 建議在 User Model 寫個轉型 function
    }

    // 登入邏輯
    @Sendable
    func login(req: Request) async throws -> UserResponse {
        struct LoginRequest: Content {
            let email: String
            let password: String
        }

        let loginData = try req.content.decode(LoginRequest.self)
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == loginData.email)
            .first() else {
            throw Abort(.unauthorized, reason: "帳號或密碼錯誤")
        }

        let isPasswordValid = try await req.password.async.verify(loginData.password, created: user.passwordHash)
        if !isPasswordValid {
            throw Abort(.unauthorized, reason: "帳號或密碼錯誤")
        }

        return user.toResponse()
    }
}
