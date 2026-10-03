import AppKit
import Foundation

/// 核心错误类型。
enum WeChatManagerError: LocalizedError {
    case wechatNotFound
    case cloneFailed(String)
    case plistModifyFailed(String)
    case resignFailed(String)
    case launchFailed(String)
    case statusQueryFailed(String)

    var errorDescription: String? {
        switch self {
        case .wechatNotFound:
            return "未在 /Applications 找到官方微信（WeChat.app），请先安装微信。"
        case .cloneFailed(let msg):
            return "创建微信实例副本失败：\(msg)"
        case .plistModifyFailed(let msg):
            return "修改实例标识失败：\(msg)"
        case .resignFailed(let msg):
            return "重签名实例失败：\(msg)"
        case .launchFailed(let msg):
            return "启动微信实例失败：\(msg)"
        case .statusQueryFailed(let msg):
            return "查询实例状态失败：\(msg)"
        }
    }
}

/// 微信多开核心引擎：
/// 1. 探测官方微信（/Applications/WeChat.app），全程不修改官方安装；
/// 2. 用 APFS clonefile 为每个实例生成隐藏受管副本（秒级、几乎零磁盘占用）；
/// 3. 修改副本 Bundle ID 并 ad-hoc 重签名，让系统与微信都认为是独立应用；
/// 4. 支持启动、状态检测、与官方微信版本同步（微信升级后自动重建副本）。
final class WeChatManager {
    static let shared = WeChatManager()

    /// 官方微信默认路径。
    let officialWeChatURL = URL(fileURLWithPath: "/Applications/WeChat.app")

    /// 受管目录：~/Library/Application Support/TianYanWeChat
    let supportDir: URL
    /// 副本根目录：<supportDir>/instances/<instanceID>/WeChat.app
    let instancesRootDir: URL

    /// 状态变化通知（状态刷新完成后发出）。
    static let statusDidRefreshNotification = Notification.Name("TianYanWeChatStatusDidRefresh")

    private init() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("无法访问 Application Support 目录")
        }
        supportDir = base.appendingPathComponent("TianYanWeChat", isDirectory: true)
        instancesRootDir = supportDir.appendingPathComponent("instances", isDirectory: true)
        try? FileManager.default.createDirectory(at: instancesRootDir, withIntermediateDirectories: true)
    }

    // MARK: - 官方微信探测

    /// 官方微信是否已安装。
    var isOfficialWeChatInstalled: Bool {
        FileManager.default.fileExists(atPath: officialWeChatURL.path)
    }

    /// 官方微信版本号。
    func officialWeChatVersion() -> String? {
        readBundleVersion(of: officialWeChatURL)
    }

    private func readBundleVersion(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    // MARK: - 实例目录

    /// 实例对应的副本 App 路径。
    func appURL(for instance: WeChatInstance) -> URL {
        instancesRootDir
            .appendingPathComponent(instance.id, isDirectory: true)
            .appendingPathComponent("WeChat.app", isDirectory: true)
    }

    /// 实例对应的数据容器路径（由系统依据 Bundle ID 生成）。
    func containerURL(for instance: WeChatInstance) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(instance.bundleIdentifier, isDirectory: true)
    }

    // MARK: - 副本创建 / 同步

    /// 确保副本存在且与官方微信版本一致；不一致时重建。
    /// 重建不删除数据容器（Bundle ID 不变 → 登录态保留）。
    func ensureInstanceApp(_ instance: WeChatInstance) throws {
        guard isOfficialWeChatInstalled else { throw WeChatManagerError.wechatNotFound }

        let appURL = appURL(for: instance)
        let exists = FileManager.default.fileExists(atPath: appURL.path)
        if exists {
            // 版本一致即复用，不一致则重建
            if let official = officialWeChatVersion(),
               let local = readBundleVersion(of: appURL),
               official == local {
                return
            }
            try? FileManager.default.removeItem(at: appURL)
        }
        try createClone(of: instance, to: appURL)
    }

    private func createClone(of instance: WeChatInstance, to appURL: URL) throws {
        let instanceDir = appURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: instanceDir, withIntermediateDirectories: true)

        // APFS clonefile：秒级完成、按块共享磁盘空间
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-cR", officialWeChatURL.path, appURL.path]
        let cpOut = Pipe(); let cpErr = Pipe()
        cp.standardOutput = cpOut; cp.standardError = cpErr
        do { try cp.run() } catch {
            throw WeChatManagerError.cloneFailed("无法执行 cp：\(error.localizedDescription)")
        }
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else {
            let err = String(data: cpErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "未知错误"
            throw WeChatManagerError.cloneFailed("cp 退出码 \(cp.terminationStatus)：\(err)")
        }

        // 修改副本 Info.plist 的 CFBundleIdentifier
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        let pb = Process()
        pb.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        pb.arguments = ["-c", "Set :CFBundleIdentifier \(instance.bundleIdentifier)", infoPlist.path]
        let pbErr = Pipe()
        pb.standardError = pbErr
        do { try pb.run() } catch {
            throw WeChatManagerError.plistModifyFailed("无法执行 PlistBuddy：\(error.localizedDescription)")
        }
        pb.waitUntilExit()
        guard pb.terminationStatus == 0 else {
            let err = String(data: pbErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "未知错误"
            throw WeChatManagerError.plistModifyFailed("PlistBuddy 退出码 \(pb.terminationStatus)：\(err)")
        }

        // 清除隔离属性，避免"无法验证开发者"提示
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-rd", "com.apple.quarantine", appURL.path]
        try? xattr.run(); xattr.waitUntilExit()

        // ad-hoc 重签名
        try resign(appURL)
    }

    private func resign(_ appURL: URL) throws {
        let cs = Process()
        cs.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        cs.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
        let csErr = Pipe()
        cs.standardError = csErr
        do { try cs.run() } catch {
            throw WeChatManagerError.resignFailed("无法执行 codesign：\(error.localizedDescription)")
        }
        cs.waitUntilExit()
        guard cs.terminationStatus == 0 else {
            let err = String(data: csErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "未知错误"
            throw WeChatManagerError.resignFailed("codesign 退出码 \(cs.terminationStatus)：\(err)")
        }
    }

    // MARK: - 启动

    /// 打开（启动/唤起）一个实例。
    func open(_ instance: WeChatInstance) throws {
        try ensureInstanceApp(instance)
        let appURL = appURL(for: instance)
        let ok = NSWorkspace.shared.open(appURL)
        guard ok else { throw WeChatManagerError.launchFailed("NSWorkspace.open 返回 false") }
        InstanceStore.shared.recordOpened(id: instance.id)
    }

    // MARK: - 官方微信（默认入口）

    /// 官方微信是否正在运行。
    /// 通过 bundleIdentifier（com.tencent.xinWeChat）识别，兼容多路径场景。
    var isOfficialWeChatRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if let bid = app.bundleIdentifier {
                return bid == "com.tencent.xinWeChat"
            }
            return app.bundleURL?.path == officialWeChatURL.path
        }
    }

    /// 打开（启动/唤起）官方原生微信。
    /// 返回 true 表示已成功启动或唤起；false 表示启动失败或未安装。
    @discardableResult
    func openOfficialWeChat() -> Bool {
        guard isOfficialWeChatInstalled else { return false }
        if isOfficialWeChatRunning {
            // 已在运行：直接唤起窗口
            for app in NSWorkspace.shared.runningApplications
            where app.bundleIdentifier == "com.tencent.xinWeChat" {
                return app.activate()
            }
        }
        return NSWorkspace.shared.open(officialWeChatURL)
    }

    // MARK: - 状态检测

    /// 该实例（副本路径）是否正在运行。
    func isRunning(_ instance: WeChatInstance) -> Bool {
        let marker = appURL(for: instance).path
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { app in
            guard let url = app.bundleURL else { return false }
            return url.path == marker
        }
    }

    /// 唤起运行中的实例窗口（若已运行则激活）。
    func activate(_ instance: WeChatInstance) -> Bool {
        let marker = appURL(for: instance).path
        for app in NSWorkspace.shared.runningApplications {
            guard app.bundleURL?.path == marker else { continue }
            return app.activate()
        }
        return false
    }
}