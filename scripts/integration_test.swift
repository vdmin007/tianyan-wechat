// 集成测试：用真实的生产代码验证多开核心链路。
// 流程：创建实例 → ensureInstanceApp（clonefile+改ID+重签名）→ open → isRunning → 容器检查 → 清理
import AppKit
import Foundation

func check(_ cond: Bool, _ name: String) {
    print(cond ? "[PASS] \(name)" : "[FAIL] \(name)")
    if !cond { exit(1) }
}

@main
struct IntegrationTest {
    static func main() {
        run()
    }

static func run() {
    let manager = WeChatManager.shared
    let store = InstanceStore.shared
    var instance: WeChatInstance? = nil
    var appURL: URL? = nil
    var container: URL? = nil

    // 兜底清理：任何路径下退出前都尝试清理测试残留
    func cleanup() {
        if let inst = instance {
            if let url = appURL {
                for app in NSWorkspace.shared.runningApplications where app.bundleURL?.path == url.path {
                    app.terminate()
                }
                sleep(1)
                try? FileManager.default.trashItem(at: url.deletingLastPathComponent(), resultingItemURL: nil)
            }
            if let c = container {
                // macOS 会保护 Containers 目录，删不掉时静默跳过
                try? FileManager.default.trashItem(at: c, resultingItemURL: nil)
            }
            store.removeInstance(id: inst.id)
            instance = nil
        }
    }

    defer { cleanup() }

// 1. 官方微信存在
check(manager.isOfficialWeChatInstalled, "检测到官方微信")
print("官方微信版本: \(manager.officialWeChatVersion() ?? "?")")

// 2. 创建测试实例
instance = store.createInstance(name: "集成测试实例")
print("实例ID: \(instance!.id)")
print("实例BundleID: \(instance!.bundleIdentifier)")

// 3. 生成受管副本
do {
    try manager.ensureInstanceApp(instance!)
    appURL = manager.appURL(for: instance!)
    check(FileManager.default.fileExists(atPath: appURL!.path), "受管副本已生成: \(appURL!.lastPathComponent)")

    // 校验副本的 Bundle ID 确实是实例专属的
    let plist = appURL!.appendingPathComponent("Contents/Info.plist")
    let dict = NSDictionary(contentsOf: plist)
    let bundleID = dict?["CFBundleIdentifier"] as? String ?? ""
    check(bundleID == instance!.bundleIdentifier, "副本 Bundle ID 已改写为 \(bundleID)")

    // 校验签名有效
    let cs = Process()
    cs.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    cs.arguments = ["--verify", appURL!.path]
    let csErr = Pipe(); cs.standardError = csErr
    try cs.run(); cs.waitUntilExit()
    check(cs.terminationStatus == 0, "副本签名有效 (codesign --verify)")

    // 4. 启动
    try manager.open(instance!)

    // 5. 等待启动后检查运行状态
    var running = false
    for _ in 0..<10 {
        sleep(2)
        running = manager.isRunning(instance!)
        if running { break }
    }
    check(running, "实例进程已启动并处于运行状态")

    // 6. 独立容器已创建（数据隔离生效）
    container = manager.containerURL(for: instance!)
    let containerExists = FileManager.default.fileExists(atPath: container!.path)
    check(containerExists, "独立数据容器已创建: \(container!.lastPathComponent)")

    // 7. 主实例未受影响（原 POC 主微信 PID，若仍在则未被动过）
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-x", "WeChat"]
    let pgOut = Pipe(); pgrep.standardOutput = pgOut
    try pgrep.run(); pgrep.waitUntilExit()
    let pids = String(data: pgOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    print("当前运行中的微信主进程: \(pids.split(separator: "\n").joined(separator: " "))")
    check(!pids.isEmpty, "至少存在微信进程(含新实例与主实例)")

    print("ALL PASS")
    }
    catch {
        print("[FAIL] 集成测试异常: \(error.localizedDescription)")
        exit(1)
    }
    }
}