import Foundation

/// 实例列表的持久化存储。
/// 配置保存在 ~/Library/Application Support/TianYanWeChat/instances.json，
/// 只包含实例元数据（名称、ID、时间），不包含任何微信账号数据。
final class InstanceStore {
    static let shared = InstanceStore()

    private(set) var instances: [WeChatInstance] = []
    private let fileURL: URL

    /// 实例列表发生变化时发出通知（AppKit 用）。
    static let didChangeNotification = Notification.Name("TianYanWeChatInstancesDidChange")

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TianYanWeChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("instances.json")
        load()
    }

    // MARK: - 查询

    func instance(byID id: String) -> WeChatInstance? {
        instances.first { $0.id == id }
    }

    // MARK: - 变更

    @discardableResult
    func createInstance(name: String?) -> WeChatInstance {
        let usedName: String = {
            let raw = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { return raw }
            let n = instances.count + 1
            return "微信 \(n)"
        }()
        var instance = WeChatInstance(name: usedName)
        // 极低概率冲突时重试
        while instances.contains(where: { $0.id == instance.id }) {
            instance = WeChatInstance(name: usedName)
        }
        instances.append(instance)
        save()
        return instance
    }

    func renameInstance(id: String, newName: String) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        instances[idx].name = trimmed
        save()
    }

    func recordOpened(id: String, at date: Date = Date()) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[idx].lastOpenedAt = date
        save()
    }

    func removeInstance(id: String) {
        instances.removeAll { $0.id == id }
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([WeChatInstance].self, from: data) else { return }
        instances = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(instances) else { return }
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}