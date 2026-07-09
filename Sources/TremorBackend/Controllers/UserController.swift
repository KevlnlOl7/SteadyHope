import Fluent
import Vapor
import JWT

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
        
        // 查資料庫，如果存在就噴 409 錯誤
        let exists = try await User.query(on: req.db)
            .filter(\.$email == data.email)
            .first() != nil
        
        if exists {
            throw Abort(.conflict, reason: "此電子郵件已被註冊")
        }
        // ----------------------------
        
        // 使用非同步雜湊（放在檢查之後省資源）
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
        return user.toResponse()
    }
    
    // 登入邏輯
    @Sendable
    func login(req: Request) async throws -> LoginResponse {
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
        
        // 在 login 函式最後修改[cite: 5]
        // 2. 產製 JWT Payload
        let payload = UserPayload(userID: user.id!, exp: .init(value: Date().addingTimeInterval(3600 * 24))) // 建議設個期限，例如24小時
        
        // 3. 簽署 Token
        let token = try req.jwt.sign(payload)
        
        // 4. 最後才 Return 整體內容
        return LoginResponse(token: token, user: user.toResponse())
    }
}
