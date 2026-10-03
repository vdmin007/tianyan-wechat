import AppKit

/// 主窗口：微信实例列表。
/// 布局：顶部工具栏（新建实例 + 微信安装状态）｜实例列表｜底部操作按钮。
final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - 组件

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let createButton = NSButton(title: "新建实例", target: nil, action: nil)
    private let openButton = NSButton(title: "打开", target: nil, action: nil)
    private let renameButton = NSButton(title: "重命名", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)

    private var refreshTimer: Timer?
    private var selectedInstanceID: String?

    private let manager = WeChatManager.shared
    private let store = InstanceStore.shared

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "天眼微信"
        window.minSize = NSSize(width: 560, height: 340)
        window.center()
        buildUI()
        refreshAll()
        startStatusTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewInstanceRequest),
            name: .tianYanRequestNewInstance,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(instancesDidChange),
            name: InstanceStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleNewInstanceRequest() {
        createInstanceTapped()
    }

    @objc private func instancesDidChange() {
        // 双保险：通知可能从未知线程发出，UI 刷新一律回到主线程
        if Thread.isMainThread {
            refreshAll()
        } else {
            DispatchQueue.main.async { self.refreshAll() }
        }
    }

    // MARK: - 界面构建

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // --- 顶部工具栏 ---
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 10
        topBar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 6, right: 14)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        createButton.target = self
        createButton.action = #selector(createInstanceTapped)
        createButton.bezelStyle = .rounded

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        topBar.addArrangedSubview(createButton)
        topBar.addArrangedSubview(statusLabel)
        contentView.addSubview(topBar)

        // --- 列表 ---
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 52
        tableView.allowsMultipleSelection = false
        tableView.addTableColumn(tableColumn(identifier: "name", title: "实例名称", width: 320))
        tableView.addTableColumn(tableColumn(identifier: "status", title: "状态", width: 110))
        tableView.addTableColumn(tableColumn(identifier: "last", title: "最近打开", width: 180))
        tableView.doubleAction = #selector(openTapped)
        tableView.target = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // --- 底部操作栏 ---
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.alignment = .centerY
        bottomBar.spacing = 10
        bottomBar.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 14, right: 14)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        openButton.target = self
        openButton.action = #selector(openTapped)
        openButton.bezelStyle = .rounded
        renameButton.target = self
        renameButton.action = #selector(renameTapped)
        renameButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.bezelStyle = .rounded

        bottomBar.addArrangedSubview(openButton)
        bottomBar.addArrangedSubview(renameButton)
        bottomBar.addArrangedSubview(deleteButton)
        contentView.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            bottomBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func tableColumn(identifier: String, title: String, width: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        col.title = title
        col.width = width
        return col
    }

    // MARK: - 数据源

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.instances.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.instances.count else { return nil }
        let instance = store.instances[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""

        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier)")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.font = NSFont.systemFont(ofSize: 13)
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch identifier {
        case "name":
            cell.textField?.stringValue = instance.name
            cell.textField?.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            cell.textField?.textColor = .labelColor
        case "status":
            let running = manager.isRunning(instance)
            cell.textField?.stringValue = running ? "● 运行中" : "○ 未运行"
            cell.textField?.textColor = running ? .systemGreen : .secondaryLabelColor
        case "last":
            if let last = instance.lastOpenedAt {
                cell.textField?.stringValue = Self.dateFormatter.string(from: last)
            } else {
                cell.textField?.stringValue = "—"
            }
            cell.textField?.textColor = .secondaryLabelColor
        default:
            break
        }
        return cell
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        selectedInstanceID = (row >= 0 && row < store.instances.count) ? store.instances[row].id : nil
    }

    // MARK: - 动作

    @objc private func createInstanceTapped() {
        let alert = NSAlert()
        alert.messageText = "新建微信实例"
        alert.informativeText = "为该实例起一个便于识别的名称："
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "例如：工作号"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let instance = store.createInstance(name: input.stringValue)
        showMainWindow()
        selectInstance(id: instance.id)
    }

    @objc private func openTapped() {
        guard let instance = selectedInstance() else { return }
        openInstance(instance)
    }

    private func openInstance(_ instance: WeChatInstance) {
        // 已运行则直接唤起
        if manager.isRunning(instance) {
            _ = manager.activate(instance)
            return
        }
        openButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try WeChatManager.shared.open(instance)
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
            DispatchQueue.main.async {
                self?.openButton.isEnabled = true
                self?.refreshAll()
            }
        }
    }

    @objc private func renameTapped() {
        guard let instance = selectedInstance() else { return }
        let alert = NSAlert()
        alert.messageText = "重命名实例"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = instance.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.renameInstance(id: instance.id, newName: input.stringValue)
    }

    @objc private func deleteTapped() {
        guard let instance = selectedInstance() else { return }
        let alert = NSAlert()
        alert.messageText = "删除实例「\(instance.name)」？"
        alert.informativeText = "删除后该实例将从列表移除。实例副本会放入废纸篓；默认保留该实例的微信登录数据（下次可重新建实例登录）。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning

        let check = NSButton(checkboxWithTitle: "同时删除该实例的微信数据（含登录状态）", target: nil, action: nil)
        let wrap = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        check.frame = NSRect(x: 0, y: 4, width: 340, height: 20)
        wrap.addSubview(check)
        alert.accessoryView = wrap

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let removeData = check.state == .on
            // 副本移入废纸篓（始终清理，释放磁盘）
            let instanceDir = self.manager.appURL(for: instance).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: instanceDir.path) {
                try? FileManager.default.trashItem(at: instanceDir, resultingItemURL: nil)
            }
            // 按用户选择决定是否连数据容器一并删除
            if removeData {
                let container = self.manager.containerURL(for: instance)
                if FileManager.default.fileExists(atPath: container.path) {
                    try? FileManager.default.trashItem(at: container, resultingItemURL: nil)
                }
            }
            DispatchQueue.main.async {
                self.store.removeInstance(id: instance.id)
            }
        }
    }

    // MARK: - 刷新

    @objc private func refreshStatusTimerFired() {
        refreshAll()
    }

    func refreshAll() {
        statusLabel.stringValue = manager.isOfficialWeChatInstalled
            ? "已检测到官方微信 v\(manager.officialWeChatVersion() ?? "?")  ·  \(store.instances.count) 个实例"
            : "未检测到官方微信，请先安装微信"
        tableView.reloadData()
        // 恢复选中
        if let sid = selectedInstanceID, let idx = store.instances.firstIndex(where: { $0.id == sid }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    private func startStatusTimer() {
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshStatusTimerFired()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - 工具方法

    private func selectedInstance() -> WeChatInstance? {
        let row = tableView.selectedRow
        guard row >= 0, row < store.instances.count else {
            showInfo("请先在列表中选择一个实例。")
            return nil
        }
        return store.instances[row]
    }

    private func selectInstance(id: String) {
        selectedInstanceID = id
        if let idx = store.instances.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
    }

    private func showMainWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showInfo(_ text: String) {
        guard window?.isKeyWindow == true else { return }
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}