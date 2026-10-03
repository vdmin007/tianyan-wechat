# 天微多开

在 macOS 上同时打开多个微信的启动/管理框架。以系统中已安装的官方微信为核心，不修改微信安装本身，通过「受管副本」技术为每个实例生成独立的微信应用副本与数据容器，实现多账号并存、互不干扰。

## 特性

- **一键多开**：点击「打开」即可拉起一个新的微信实例，与已有微信共存
- **实例管理**：新建、重命名、删除实例；列表实时显示运行状态与最近打开时间
- **数据隔离**：每个实例使用独立的 Bundle ID 与独立的数据容器，多账号登录互不冲突
- **无感副本**：基于 APFS clonefile 的快照副本，秒级生成、磁盘几乎零占用（逻辑大小同官方微信，实际仅占用增量数据）
- **不新增软件**：副本由本软件自动管理，不向「应用程序」目录写入任何可见的新应用
- **零修改**：不修改、不复制到用户层可见位置的官方微信安装（/Applications/WeChat.app 原样保留）
- **菜单栏常驻**：托盘图标常驻菜单栏，随时管理实例

## 系统要求

- macOS 12.0 及以上（当前已在 macOS 27 / Apple Silicon 上验证）
- 已安装官方微信（/Applications/WeChat.app），本软件以它为核心工作
- 使用 Swift 6.x 工具链可自行构建（Xcode / Command Line Tools）

## 安装（.pkg 安装包）

预构建安装包：`dist/天微多开-1.0.3.pkg`。

- **图形安装**：双击 `.pkg` 按引导安装（默认安装到 `/Applications/天微多开.app`，自动覆盖旧版并清理旧英文目录）。
- **静默安装**：`sudo installer -pkg dist/天微多开-1.0.3.pkg -target /`
- **Gatekeeper 提示**：本机未配置 Apple Developer 签名，安装时若提示「无法验证开发者」，在访达中右键该安装包 →「打开」→「打开」即可；命令行安装不受影响。

**版本管理规则（内置，自动生效）**：

| 本机已安装情况 | 安装包行为 |
| --- | --- |
| 未安装 | 正常安装 |
| 旧版本（如 1.0.2）或旧命名 TianYanWeChat.app | **自动覆盖升级**至「天微多开」，无需先手动删除 |
| 相同版本（如 1.0.3） | **阻止重复安装**，提示先手动删除后再装 |
| 更新版本（如 1.1.0） | **阻止降级覆盖**，提示先手动删除后再装 |

规则由安装包内置的 `preinstall` 脚本实现，可通过 `scripts/test-preinstall.sh` 复验（未安装/旧版/同版/新版/旧命名迁移 五种场景全部断言通过）。

## 使用说明

### 1. 获取应用

方式 A：直接使用预构建产物 `dist/天微多开.app`，拖入「应用程序」文件夹即可（如无需常驻，直接双击运行也可）。

方式 B：本地构建（见「从源码构建」）。

### 2. 默认微信（官方入口）

- 列表**第 0 行固定为「微信（默认）」**，对应你本机已安装的官方微信 `/Applications/WeChat.app`，**不可删除、不可重命名**。
- 选中该行点击「打开」（或直接双击），即可启动官方原生微信；若微信已在运行则会直接唤起其窗口。
- 状态列实时显示官方微信的运行状态：运行中显示「● 运行中」，否则显示「○ 未运行」。

### 3. 新建并打开实例

1. 打开「天微多开」主窗口（首次启动自动弹出；也可通过菜单栏图标 →「显示主窗口」）。
2. 点击「新建实例」，输入这个微信的身份名称（如「工作号」「生活号」）。
3. 在列表中选择该实例，点击「打开」：
   - 第一次打开时自动完成副本生成、Bundle ID 改写、重签名，之后为秒开；
   - 会弹出一个正常的微信登录窗口，扫码登录即可，与其它实例互不影响。
4. 状态列显示该实例当前是否在运行；再次点击「打开」会唤起对应微信窗口。

> 提示：第 2 个及以后的实例会自动使用四分之一的“缩略”窗口模式（与系统多开行为一致），展开后即可正常使用。

### 3. 重命名 / 删除实例

- 选中实例后点击「重命名」修改名称（仅改变显示名，不影响已登录账号与数据）。
- 选中实例后点击「删除」移除该实例记录与其受管副本。该实例的数据容器会保留（见「常见问题」），方便日后找回数据或彻底清理。

### 4. 菜单栏

菜单栏常驻图标提供：显示主窗口、新建实例、退出。关闭主窗口后应用仍在后台运行（下次打开秒启）。

## 从源码构建

```bash
# 在工程根目录执行
./build.sh release
```

产物输出到 `dist/天微多开.app`（内部可执行文件名保持 TianYanWeChat，不改动 SwiftPM target）。构建过程：`swift build -c release` → 组装 .app 目录 → 写入 Info.plist → ad-hoc 签名。

依赖：macOS 上的 Swift 工具链（`swift`、`codesign` 随 Command Line Tools 提供）。无需任何第三方依赖。

## 项目结构

```
tianyan-wechat/
├── Package.swift                    # SwiftPM 工程定义
├── build.sh                         # 一键构建脚本（编译+组装.app+重签名）
├── build-installer.sh               # 安装包构建脚本（pkgbuild + productbuild）
├── installer/
│   ├── scripts/preinstall           # 版本门控：旧版自动覆盖、同版/新版阻止重装
│   ├── scripts/postinstall          # 安装后收尾（权限修复）
│   └── resources/                   # 安装向导页面与 distribution.xml
├── Sources/TianYanWeChat/
│   ├── main.swift                   # 应用入口
│   ├── App/AppDelegate.swift        # 应用生命周期与菜单栏常驻
│   ├── Core/WeChatManager.swift     # 核心引擎：官方微信探测、受管副本生成、
│   │                                #   改 Bundle ID、重签名、启动/状态检测
│   ├── Models/WeChatInstance.swift  # 实例数据模型
│   ├── Store/InstanceStore.swift    # 实例列表 JSON 持久化
│   └── UI/MainWindowController.swift# 主窗口：实例列表表格与操作按钮
├── scripts/integration_test.swift   # 核心链路集成测试（可独立编译运行）
├── scripts/test-preinstall.sh       # 安装包版本门控单元测试（五场景断言）
└── README.md                        # 本文档
```

### 数据与文件位置

| 内容 | 位置 |
| --- | --- |
| 实例列表配置 | `~/Library/Application Support/TianYanWeChat/instances.json` |
| 受管副本 | `~/Library/Application Support/TianYanWeChat/instances/<实例ID>/WeChat.app` |
| 实例独立数据 | `~/Library/Containers/com.tencent.xinWeChat.<实例ID>/`（微信自动创建） |
| 官方微信安装 | `/Applications/WeChat.app`（全程只读访问，不受影响） |

## 工作原理（重要）

macOS 官方微信默认只允许运行一个实例（单实例检测在微信应用自身逻辑层）。经实测，`open -n`、直接启动二进制、环境变量隔离等“零复制”方案均被微信 4.1.13 的单实例检测拦截（详见需求文档的技术路线对比）。

「天微多开」采用**受管副本**路线：

1. 用 APFS clonefile（`cp -cR`）从官方微信生成一份逻辑副本（秒级、磁盘增量几乎为零）；
2. 改写副本的 `CFBundleIdentifier` 为 `com.tencent.xinWeChat.<实例ID>`，使 macOS 将其识别为独立应用；
3. 清除隔离属性并用 `codesign` 做 ad-hoc 重签名，保证系统可正常启动；
4. 启动后微信以自己的副本身份运行，自动创建独立数据容器，原实例完全不受影响。

由此：**不修改、不删除官方安装**；副本仅存在于本软件自有目录中，不增加可见的新软件；每个实例一份独立身份与独立数据。

> 合规说明：副本属于自动生成的临时运行体，与“复制并修改微信安装”有本质区别——官方安装从未被触碰；删除实例即自动移除对应副本。本软件未做任何进程注入、协议破解或防撤回等客户端改造，多开本身依赖系统应用层机制实现。

## 常见问题

**Q：打开实例后微信没反应？**
A：首次生成副本需 1~2 秒，稍等片刻；若状态仍为「未运行」，请确认官方微信可正常打开、且磁盘空间充足。删除该实例后重新新建再打开。

**Q：第二个微信窗口很小？**
A：这是系统对多实例应用的默认行为，拖拽窗口边框即可调整，与功能无关。

**Q：删除实例后，数据容器还在？**
A：出于数据安全考虑，删除实例仅移除记录与其受管副本，微信的数据容器默认保留（防止误删聊天记录）。确认无需保留时，可在访达中前往 `~/Library/Containers/`，手动删除 `com.tencent.xinWeChat.<实例ID>` 文件夹即可腾出空间。

**Q：官方微信更新后，实例副本需要重建吗？**
A：需要。微信更新后副本仍是旧版本，更新官方微信后删除已有实例并重新新建即可获得新版副本。

**Q：会不会被封号？**
A：本工具不修改任何微信客户端行为、不做协议层介入，仅提供系统级的多实例启动；请使用官方微信登录界面正常登录。云服务条款以腾讯官方规则为准。

**Q：Intel Mac 能用吗？**
A：工程为纯 Swift 编写、不依赖架构；在 Intel Mac 上重新构建即得 Intel 版本。当前默认优先支持 Apple Silicon。

**Q：安装后应用图标还是旧的 / 没有显示新图标？**
A：macOS 会用 LaunchServices 缓存应用图标。本安装包已内置刷新逻辑：安装完成时自动注销并重新注册应用（`lsregister -u/-f` 并 `touch` 应用包）。若个别机器仍显示旧图标，可手动刷新：在「活动监视器」或终端执行 `killall Dock`（Dock 会重启），或在终端运行：
```
rm -rf ~/Library/Caches/com.apple.iconservices.store
killall Dock
```
图标即会重新构建。

## 卸载

1. 在「天微多开」中删除全部实例；
2. 将应用拖入废纸篓；
3. （可选）删除 `~/Library/Application Support/TianYanWeChat/` 与 `~/Library/Containers/com.tencent.xinWeChat.<实例ID>`/。

官方微信安装及其数据全程不受影响。

## 集成测试

核心链路（副本生成 → 改 Bundle ID → 重签名 → 启动 → 状态检测 → 数据隔离）已通过自动化集成测试验证：

```bash
swiftc -o /tmp/ty_it \
  Sources/TianYanWeChat/Models/WeChatInstance.swift \
  Sources/TianYanWeChat/Store/InstanceStore.swift \
  Sources/TianYanWeChat/Core/WeChatManager.swift \
  scripts/integration_test.swift && /tmp/ty_it
```

全部断言 PASS 即代表多开核心链路正常。测试会自动清理产生的副本与记录。

安装包版本门控另有单元测试（构造假 app 校验 preinstall 的覆盖/阻止行为）：

```bash
bash scripts/test-preinstall.sh
```

预期输出 `结果: 5 通过 / 0 失败`。