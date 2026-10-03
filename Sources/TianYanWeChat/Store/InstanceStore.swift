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
        // 可能在后台线程被调用（WeChatManager.open 的后台任务），
        // 列表变更必须回到主线程，避免并发修改 + 非主线程 UI 刷新导致崩溃。
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.recordOpened(id: id, at: date) }
            return
        }
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
        // save() 使用 .iso8601 编码日期；老数据可能是默认格式，两种都尝试
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let decoded = try? iso.decode([WeChatInstance].self, from: data) {
            instances = decoded
            return
        }
        let legacy = JSONDecoder()
        legacy.dateDecodingStrategy = .deferredToDate
        if let decoded = try? legacy.decode([WeChatInstance].self, from: data) {
            instances = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(instances) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // 通知强制在主线程发出，观察者（表格刷新）依赖主线程执行
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }
}