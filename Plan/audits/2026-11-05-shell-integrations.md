# 审计报告 — 应用外壳与平台集成（2026-11-05）

范围：`ui/main/`（MainActivity、底部标签、书架片段、顶层导航、我的）、通知、深链接、文件关联/打开方式、分享、应用更新检查、本地 Web 服务（`web/` HTTP + WebSocket）、桌面快捷方式。

上游 = `D:\code\vscode\legado`（路径相对 `app/src/main/`），移植 = `D:\code\vscode\legado-ios`（路径相对仓库根）。只读审计，未修改任何文件。

| 上游功能 | 上游证据 | 移植端最接近的代码 | 状态 |
|---|---|---|---|
| 首次启动的隐私政策同意门（同意/拒绝） | `ui/main/MainActivity.kt:200-216`（`privacyPolicy()` → `LocalConfig.privacyPolicyOk`，拒绝 → `finish()`） | `Sources/LegadoCore/App/LocalConfig.swift:42-45`（标志 `privacyPolicyOk` 存在但没有任何 UI 写入）；文档视图 `Sources/LegadoUI/AboutDocuments.swift:39/:59/:148`；`Sources/LegadoUI/RootView.swift:32-106` 里**没有门** | **缺失** |
| 启动时的首次运行帮助/更新日志对话框 | `MainActivity.kt:221-244`（`upVersion()` → 首次打开 `web/help/md/appHelp.md`，否则 `updateLog.md`，TextDialog MD） | `Sources/LegadoUI/MineViews.swift:659-661`（更新日志只在"关于"里）；`Sources/LegadoServer/Resources/WebUI/help/md/appHelp.md` 只是 web 服务资源 | **部分** |
| 启动时的崩溃对话框（"检测到阅读发生了崩溃" → CrashLogsDialog） | `MainActivity.kt:273-284`（`notifyAppCrash()`） | `Sources/LegadoUI/MineViews.swift:677-680`（崩溃日志只在"关于"里，启动时没有提示） | **部分** |
| 启动时按 `AppConfig.autoRefreshBook` 自动刷新全部书籍 | `MainActivity.kt:129-135`（`if (AppConfig.autoRefreshBook && !isAutoRefreshedBook) viewModel.upAllBookToc()`） | 开关存在 `Sources/LegadoUI/OtherSettingsView.swift:75-78`；`updateAllBooks()` 的唯一调用者是手动的"更新目录" `Sources/LegadoUI/BookshelfView.swift:93-95` ⇒ 该偏好启动时无效 | **缺失** |
| 按配置的默认标签启动（`AppConfig.defaultHomePage` = 书架/发现/订阅/我的） | `MainActivity.kt:385-398`（`upHomePage()`） | Picker 存在 `Sources/LegadoUI/OtherSettingsView.swift:91-98`（标签 书架/发现/订阅，无"我的"）；`Sources/LegadoUI/RootView.swift:37-60` 的 TabView **没有 `selection:` 绑定** ⇒ 永远打开书架；`defaultHomePage` 从未被读取 | **缺失** |
| 退出应用时的每日自动备份 | `MainActivity.kt:315-323` → `help/storage/Backup.kt:99-121`（`autoBack(context)`，每天一次） | 只有手动的"立即备份" `Sources/LegadoUI/BackupView.swift:57`；`Sources/` 里 grep `scenePhase\|backgroundTask\|autoBackUp` 无命中 | **部分** |
| "我的" → 帮助（appHelp.md） | `ui/main/my/MyFragment.kt:70`（`R.id.menu_help -> showHelp("appHelp")`） | `Sources/LegadoUI/SettingsView.swift`（整个"我的"表单，311 行）没有帮助入口；appHelp.md 只存在于 `Sources/LegadoServer/Resources/WebUI/` | **缺失** |
| 启动时申请通知权限 + 注册通知分类 | `App.kt:179-222`（`createNotificationChannels`: download/readAloud/web） | `Sources/LegadoUI/Notifications.swift:36-70`（`prepare()`），但**只**被 `Sources/LegadoApp/LegadoAppMain.swift:39`（SwiftPM/CLI 可执行文件）调用；真正的 iOS 应用 `Sources/LegadoAppUI/LegadoAppIOS.swift`（36 行）没有 `init()`、没有 AppDelegate、没有 `UNUserNotificationCenterDelegate`，从不调用 `prepare()` ⇒ iOS 上既不授权也不注册分类 | **缺失**（阻塞所有通知） |
| 朗读的媒体通知（6 个播放按钮） | `service/BaseReadAloudService.kt:594-681`（media style、CATEGORY_TRANSPORT、6 个 action） | 模型已移植 `Sources/LegadoCore/App/Notifications.swift:59-66` + 分类 `Sources/LegadoUI/Notifications.swift:43-69`；在 `Sources/LegadoUI/ReadAloudPlatform.swift:387-397` 发布（`Sources/LegadoUI/ReaderView.swift:244` 接线）—— 但分类从未注册（上一行）⇒ 按钮无法出现/工作 | **部分** |
| 后台进度通知：下载/缓存/导出/校验书源 | `service/DownloadService.kt:227-267`、`CacheBookService.kt:51-184`、`ExportBookService.kt:136-163`、`CheckSourceService.kt:63-258` | 内容模型存在 `Sources/LegadoCore/App/Notifications.swift:105-115`（`download`）与 `:201-204`（`downloadProgress`），但 grep **找不到发布点**；移植端唯一的 `post(...)` 是朗读 | **缺失** |
| 本地 Web 服务的前台通知（复制地址/停止） | `service/WebService.kt:197-212`（+ `:118` 的 action） | `Sources/LegadoCore/App/Notifications.swift:144-151` 定义了 `NotificationContent.webService`，从未发布（服务本身也不存在，见下） | **缺失** |
| "下载本书"的后台文件下载（带通知的服务） | `model/Download.kt:8-18` → `service/DownloadService.kt` | 没有逐章下载动作；只有离线缓存对话框 `Sources/LegadoUI/DownloadViews.swift:25` | **缺失** |
| 本地 HTTP/WebSocket 服务真正运行，并由"启用本地服务"偏好启动/停止 | `service/WebService.kt`（前台服务，HTTP 在 `webPort`，WS 在 port+1）+ `MyFragment.kt:128-139` | `Sources/LegadoServer/LegadoServer.swift:85`（`public func start() throws -> Int`）只在 `Tests/LegadoServerTests/*` 与 `Sources/LegadoApp/LegadoSmokeTest.swift:141` 被实例化；应用目标从不调用它。`Sources/LegadoUI/SettingsView.swift:187`（Toggle 启用本地服务）与 `:191`（TextField 服务端口）只写偏好 ⇒ 发布的应用什么都不服务 | **缺失** |
| 显示并可复制服务器地址（hostAddress；长按 → 复制地址/浏览器打开） | `MyFragment.kt:83-104`（summary = `WebService.hostAddress`，`sendToClip(summary)` / `openUrl(summary)`） | `Sources/LegadoUI/OtherSettingsView.swift:195` 只显示"Web服务端口：\(settings.webPort)" —— 没有地址、没有复制、没有在浏览器打开 | **缺失** |
| 深链接路径 `/readConfig`（从 URL 导入阅读配置） | `ui/association/OnLineImportActivity.kt:81-86`（`viewModel.getBytes(url) { importReadConfig(bytes) }`） | `Sources/LegadoCore/App/DeepLink.swift:157-178`（`kind(forPath:host:)`）没有 `/readConfig` 分支 | **缺失** |
| 深链接路径 `/addToBookshelf`（按 URL 把书加入书架） | `OnLineImportActivity.kt:84-86`（`AddToBookshelfDialog(url, true)`） | 同上 —— 没有分支 | **缺失** |
| 深链接路径 `/theme`（导入主题） | `OnLineImportActivity.kt:78-80`（`ImportThemeDialog`） | `Sources/LegadoCore/App/DeepLink.swift:250` → `throw DeepLinkError.unsupportedKind(kind)` | **缺失** |
| `yuedu://` URL scheme（旧别名） | `AndroidManifest.xml:337-352`（同时注册 `legado` 与 `yuedu`） | `Sources/LegadoAppUI/Info.plist` 的 `CFBundleURLTypes` 只注册 `legado`；`Sources/LegadoCore/App/DeepLink.swift:103` 对其它 scheme 抛 `.wrongScheme` | **缺失**（很便宜） |
| 深链接导入前的确认对话框 | `OnLineImportActivity.kt:58-100`（每个分支都弹 Import*Dialog 询问） | `Sources/LegadoUI/DeepLinkHandler.swift:52-63` + `Sources/LegadoCore/App/DeepLink.swift:188-211` 直接静默导入 | **部分**（行为差异） |
| 打开压缩包时解压并导入其中的每一本书 | `ui/association/FileAssociationViewModel.kt:19-65`（`ArchiveUtils.deCompress` → 分发每一本书） | `Sources/LegadoUI/DeepLinkHandler.swift:133` 回答"暂不支持直接打开压缩包"，尽管引擎能解压（`Sources/LegadoUI/AppModel.swift:498-508` `importLocalBooks`） | **部分** |
| "打开方式"支持的文件类型（mobi/azw/azw3/octet-stream、.zip/.rar/.7z…） | `AndroidManifest.xml:363-452`（text/plain、application/json、epub+zip、pdf、mobi、x-mobipocket-ebook、azw、azw3、x-mobi8-ebook、octet-stream + 路径模式 .txt .json .epub .pdf .mobi .azw .azw3 .zip .rar .7z） | `Sources/LegadoAppUI/Info.plist` 的 `CFBundleDocumentTypes` 只有 public.plain-text、public.json、org.idpf.epub-container、com.adobe.pdf（×2）—— 检测代码认识 mobi/azw3/azw（`Sources/LegadoCore/App/FileAssociation.swift:33`）但 iOS 从不把这些文件交给应用 | **部分** |
| 把文本分享进应用（ACTION_SEND / ACTION_PROCESS_TEXT → 搜索或打开） | `receiver/SharedReceiverActivity.kt:13-59` | 没有 Share Extension / 应用扩展目标：`project.yml:16-47` 只定义了 `LegadoApp`；`Sources/LegadoAppUI/Info.plist` 没有 `NSExtension` | **缺失** |
| 桌面快捷方式（最近阅读/朗读/书架） | `api/ShortCuts.kt:1-63`（`setDynamicShortcuts`），基于 `api/ReaderProvider.kt:55` | grep `shortcutItem\|UIApplicationShortcut` 无命中；Info.plist 里没有 `UIApplicationShortcutItems` | **缺失**（上游**没有** AppWidget，无可移植） |
| 测试版更新通道（`AppConfig.updateToVariant` 是 beta 变体时用 `/releases/tags/beta`） | `help/update/AppUpdateGitHub.kt:27-49` | `Sources/LegadoCore/App/AppUpdate.swift` 的 `releaseURL` 永远是稳定的 `releases/latest` | **轻微缺失** |
| 关于 → 邮箱（sendMail）与公众号（复制 gzGzh 文本） | `ui/about/AboutFragment.kt:61`（`mail -> sendMail(...)`）、`:65`（`gzGzh -> sendToClip(R.string.legado_gzh)`） | `Sources/LegadoUI/MineViews.swift:643-715`（AboutView）没有邮箱/公众号入口 | **轻微缺失** |

## 只属于 Android、不应移植的项

- **AppWidget / 桌面小组件** —— 上游没有（`res/` 里没有 widget xml）；唯一类似的是长按的动态快捷方式，而 iOS 只支持**静态**快捷方式，所以 `api/ReaderProvider.kt:55` 的 ContentProvider 刷新在这里没有意义（正确的等价物是一个静态的 `UIApplicationShortcutItems` 数组）。
- **QS 磁贴 `WebTileService`**（Web 服务的快捷设置磁贴）—— iOS 无对应物；移植端应当改为应用内的启动/停止 + 地址（目前缺失）。
- **前台服务机制**（前台服务 + 唤醒锁偏好 `webServiceWakeLock` + 网络变化监听）in `service/WebService.kt` —— iOS 上本地服务只能在应用处于前台时运行；不要模仿服务，只从 UI 启动/停止。
- **`FileProvider` + `externalCacheDir/qr.png` + `ACTION_SEND image/png`**（`utils/ContextExtensions.kt:280-306`）—— 已由 `Sources/LegadoUI/QRCodeView.swift`（CIQRCodeGenerator）+ `Sources/LegadoUI/ShareSheet.swift`（UIActivityViewController）正确替代。
- **Android DownloadManager / APK 安装**（更新的安装包资产）—— 移植端链接到发布页；iOS 上安装走 App Store/TestFlight，所以 `downloadURL(in:)` 的 `.apk` 分支无害但不应做安装器。
- **Android 堆转储**（`ui/about/AboutFragment.kt:143-165` `createHeapDump`）—— iOS 无对应物（移植端存的是 iOS 的崩溃报告，不需要）。
- **双击返回退出**手势与**"退出"偏好**（`MainActivity.kt:104-113`、`res/xml/pref_main.xml:121`、`MyFragment.kt:167`）—— iOS 应用不应主动退出。
- **`ACTION_SEND`/`ACTION_PROCESS_TEXT` 接收器的语义**（`receiver/SharedReceiverActivity.kt`）—— Android 的分享意图管道；若在 iOS 上需要，必须做成 Share Extension，而不是移植接收器。
- **媒体键耳机处理**（`receiver/MediaButtonReceiver.kt`）—— 已由 `Sources/LegadoUI/MediaCommandBridge.swift`（MPRemoteCommandCenter）覆盖；无需再移植。

## 结论

在本领域移植端几乎完整地复现了上游的**广度**，但缺少**接线**：**25 个缺口 —— 16 个缺失，9 个部分/轻微**。最大的三个是：

1. **本地 HTTP/WebSocket 服务在发布的 iOS 应用里从未启动** —— `Sources/LegadoServer` 里已完整实现并单元测试（全部 26 条上游路由、3 个 WebSocket 端点、逐字复制的上游 Vue Web UI），但"启用本地服务"的 Toggle 只写偏好，服务器地址也从不显示/复制。
2. **iOS 上通知实际上是死的** —— `NotificationService.prepare()`（权限 + 分类注册）只被 CLI 可执行文件调用，真正的应用目标 `Sources/LegadoAppUI/LegadoAppIOS.swift` 从不调用；下载/缓存/导出/校验书源的进度通知完全没有发布点。
3. **MainActivity 的启动生命周期基本缺失** —— 没有隐私政策门、没有首次运行的帮助/更新日志、没有崩溃提示、没有启动时自动刷新书籍、`defaultHomePage` 的 Picker 是无效的（TabView 没有 `selection:`）、退出时也没有每日自动备份。

平台集成侧在深链接/文件关联上也被削减（没有 `/readConfig`、`/addToBookshelf`、`/theme` 路径，没有 `yuedu` scheme，导入前没有确认，拒绝压缩包，Info.plist 里没有 mobi/azw/zip 文档类型），另外没有"分享进应用"的扩展，也没有桌面快捷方式。

相比之下，纯应用内逻辑的部分 —— 四个标签及其可见性规则、整个书架工具栏菜单、"我的"偏好界面、本地密码提示、WebDAV 新备份检查、分享/二维码/剪贴板、GitHub 更新检查、媒体/锁屏控制以及朗读通知的**模型** —— 都已移植，不应列为缺口。
