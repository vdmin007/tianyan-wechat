import Foundation

/// 一个微信多开实例的元数据。
struct WeChatInstance: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdAt: Date
    var lastOpenedAt: Date?

    /// 该实例专属的 Bundle Identifier。
    /// 每个实例拥有独立 Bundle ID，系统据此为它生成独立数据容器，
    /// 从而实现登录态与数据完全隔离。
    var bundleIdentifier: String {
        "com.tencent.xinWeChat.\(id)"
    }

    init(id: String = Self.makeID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }

    static func makeID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}