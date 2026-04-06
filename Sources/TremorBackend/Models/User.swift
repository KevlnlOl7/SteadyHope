import Fluent    // 必須導入，否則不認識 Model, ID, Field
import Vapor     // 必須導入，否則不認識 Content
import Foundation // 必須導入，否則不認識 Date

final class User: Model, Content, @unchecked Sendable{
    static let schema = "users"

    @ID(custom: .id)var id: Int?
    @Field(key: "email")var email: String
    @Field(key: "password_hash")var passwordHash: String
    @Field(key: "birth")var birth: Date?
    @Field(key: "name") var name: String?
    @Field(key: "gender") var gender: Int?
    @Field(key: "disease_stage") var diseaseStage: String?

    init() {}

    init(id: Int? = nil, email: String, passwordHash: String, birth: Date?,name:String? , gender:Int?,diseaseStage:String?) {
        self.id = id
        self.email = email
        self.passwordHash = passwordHash
        self.birth = birth
        self.name = name
        self.gender = gender
        self.diseaseStage = diseaseStage
    }
    func toResponse() -> UserResponse {
            return UserResponse(
                id: self.id,
                email: self.email,
                name: self.name,
                birth: self.birth,
                gender: self.gender,
                diseaseStage: self.diseaseStage
            )
        }
}
