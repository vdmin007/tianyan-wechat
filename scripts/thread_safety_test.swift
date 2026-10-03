// 天眼微信 线程安全回归测试
// 复刻崩溃链路: 后台线程 recordOpened -> save 通知 -> 观察者 reloadData
// 修复前: 通知在后台线程发出, reloadData 非主线程 -> NSTableView 崩溃(SIGABRT)
// 修复后: 数据变更与通知强制回主线程, reloadData 在主线程 -> 正常运行
//
// 用法: swiftc -o /tmp/thread_safety_test \
//         Sources/TianYanWeChat/Models/WeChatInstance.swift \
//         Sources/TianYanWeChat/Store/InstanceStore.swift \
//         scripts/thread_safety_test.swift
//       /tmp/thread_safety_test
import Foundation
import AppKit

let store = InstanceStore.shared
guard let first = store.instances.first else {
    print("FAIL: 无实例可测（先通过应用新建一个实例）")
    exit(1)
}

let start = Date()
var notifiedOnMain = false
var reloadDone = false
var reloadError: String? = nil

let obs = NotificationCenter.default.addObserver(
    forName: InstanceStore.didChangeNotification, object: nil, queue: nil
) { _ in
    let isMain = Thread.isMainThread
    print("  [通知回调] 线程 isMainThread=\(isMain)")
    notifiedOnMain = isMain
    // 复刻 MainWindowController.refreshAll() 的 UI 操作
    let tv = NSTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
    tv.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
    tv.reloadData()
    reloadDone = true
    reloadError = nil
}

print("==> 后台线程触发 recordOpened（模拟 WeChatManager.open 链路）")
DispatchQueue.global(qos: .userInitiated).async {
    store.recordOpened(id: first.id, at: Date())
}

// 驱动主线程 runloop 等待通知与刷新完成
while !reloadDone && Date().timeIntervalSince(start) < 6 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

print("==> 结果")
var pass = true
if !reloadDone {
    print("FAIL: 通知/刷新未在超时内完成")
    pass = false
} else if !notifiedOnMain {
    print("FAIL: 通知在非主线程发出（修复未生效）")
    pass = false
} else {
    print("PASS: 通知在主线程发出、表格刷新完成、进程未崩溃")
}
if let err = reloadError {
    print("崩溃异常: \(err)")
    pass = false
}
// 验证数据已更新
if let updated = store.instance(byID: first.id), updated.lastOpenedAt != nil {
    print("PASS: lastOpenedAt 已更新")
} else {
    print("FAIL: lastOpenedAt 未更新")
    pass = false
}

NotificationCenter.default.removeObserver(obs)
print(pass ? "==> 全部通过" : "==> 存在失败")
exit(pass ? 0 : 1)