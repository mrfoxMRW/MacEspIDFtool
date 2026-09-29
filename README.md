# MacEspIDFtool（mac 分支）

---

## 📦 项目总结：MacEspIDFtool（mac 分支）

### 项目定位
Mac 平台上的 **ESP32-S3 日志只读查看工具**：通过 USB 串口抓取 ESP-IDF 运行时日志，快速复制日志，异常高亮显示。

---

### ⚙️ 核心功能

| 功能 | 说明 |
|---|---|
| **端口扫描** | 自动检测串口，优先标记疑似 ESP32 设备 |
| **只读连接** | 打开后立即清除 DTR/RTS，**绝不触发芯片复位**（核心铁律） |
| **日志解析** | 正则识别 ESP-IDF 行：`级别 (CPU0) tag: 消息`，按级别着色（V/D/I/W/E） |
| **Tag 过滤** | 不区分大小写子串匹配，即时过滤；**过滤作用于全部历史行**（修复后） |
| **级别过滤** | 按最小级别过滤（V10 < D20 < I30 < W40 < E50） |
| **历史重放** | 全量 history 缓冲 + `applyFilter()` 整体重渲染，改条件即刻重筛 |
| **日志保存** | 连接期间可落盘保存，另支持 `saveLine` 单行持久化 |
| **状态栏提示** | 过滤生效时显示"过滤中: Tag: xxx ≥ I" |
| **帮助菜单** | 定制显示工具名、开发者、版权信息 |
| **Liquid Glass 图标** | iOS 26/macOS 26 新 `.icon` 格式，全尺寸自动渲染 |

---

### 🛠 构建体系（双通道）

1. **Xcode 工程**（当前主用）：`xcodebuild -configuration Release`，产物含 `Assets.car`（Liquid Glass 图标全套渲染）
2. **SwiftPM 备用**：`swift build -c release` + `build_app.sh` 组装 .app（生成 `AppIcon.icns`）
3. 部署方式：`python3 shutil.copytree` 覆盖（规避外部卷 trash 权限问题）

---

### 🧩 技术要点

- **并发模型**：串口读取在后台线程，`NSLock` 保护 history 缓冲，主线程做过滤重渲染
- **SwiftUI 写法**：`.onChange(of:) { _, _ in }` 双参数新写法（部署目标 macOS 14.0）



