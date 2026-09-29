import SwiftUI
import AppKit

/// 日志会话控制器：端口扫描、只读连接、读取循环、过滤、保存、回放
final class LogViewModel: ObservableObject {
    @Published var ports: [SerialPortInfo] = []
    @Published var selectedPort: String?
    @Published var baud: Int = 115200
    @Published var isConnected = false
    @Published var statusText = "未连接"
    @Published var lineCount = 0
    @Published var tagFilter = ""
    @Published var minLevel: LogLevel?
    @Published var isSaving = false
    @Published var savePath: String?

    let console = LogConsole()

    private var serial: SerialPort?
    private var saveHandle: FileHandle?
    private var readLoopActive = false

    // 全量日志历史（读取线程追加，主线程过滤重渲染）
    private let historyLock = NSLock()
    private var history: [ESPLogEntry] = []

    var filterSummary: String {
        var parts: [String] = []
        if !tagFilter.isEmpty { parts.append("Tag: \(tagFilter)") }
        if let min = minLevel { parts.append("≥ \(min.displayName)") }
        return parts.joined(separator: " ")
    }

    private func currentFilter() -> LogFilter {
        var filter = LogFilter()
        filter.minLevel = minLevel
        if !tagFilter.isEmpty {
            filter.tags = [tagFilter]
        }
        return filter
    }

    private func appendToConsole(_ entry: ESPLogEntry) {
        let display = ESPLogParser.displayText(entry: entry)
        let color = ESPLogParser.parse(line: entry.raw)?.level.color
        console.appendLine(display, color: color)
    }

    /// 按当前过滤条件重渲染整个控制台（过滤变更时由主线程调用）
    func applyFilter() {
        historyLock.lock()
        let snapshot = history
        historyLock.unlock()
        let filter = currentFilter()
        console.clear()
        var count = 0
        for entry in snapshot where filter.accepts(entry) {
            appendToConsole(entry)
            count += 1
        }
        lineCount = count
    }

    func clearHistory() {
        historyLock.lock()
        history.removeAll()
        historyLock.unlock()
    }

    // MARK: - 端口

    func refreshPorts() {
        ports = SerialPortScanner.detect()
        if selectedPort == nil, let first = ports.first(where: { $0.isLikelyESP }) ?? ports.first {
            selectedPort = first.path
        }
    }

    // MARK: - 连接 / 断开（只读）

    func toggleConnect() {
        isConnected ? disconnect() : connect()
    }

    func connect() {
        guard !isConnected, let path = selectedPort else { return }
        let port = SerialPort(path: path, baud: baud)
        do {
            try port.open()
            serial = port
            isConnected = true
            statusText = "已连接 \(path) @ \(baud) baud（只读，不复位）"
            startReadLoop()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func disconnect() {
        readLoopActive = false
        serial?.close()
        serial = nil
        isConnected = false
        stopSaving()
        statusText = "已断开"
    }

    // MARK: - 读取循环（后台线程）

    private func startReadLoop() {
        guard let serial else { return }
        readLoopActive = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var buffer = Data()
            while self.readLoopActive, serial.isOpen {
                do {
                    let chunk = try serial.readChunk(timeoutMs: 100)
                    guard !chunk.isEmpty else { continue }
                    buffer.append(contentsOf: chunk)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let raw = buffer.prefix(upTo: nl)
                        buffer.removeSubrange(buffer.startIndex...nl)
                        guard
                            let bytes = String(data: Data(raw), encoding: .utf8)
                        else { continue }
                        let line = bytes.replacingOccurrences(of: "\r", with: "")
                        if !line.isEmpty {
                            self.processLine(line)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.statusText = "读取错误: \(error.localizedDescription)"
                    }
                    break
                }
            }
        }
    }

    private func processLine(_ line: String) {
        let entry = ESPLogEntry(
            timestamp: ESPLogParser.nowStamp(),
            raw: line,
            level: nil,
            tag: nil,
            message: nil
        )
        historyLock.lock()
        history.append(entry)
        historyLock.unlock()
        guard currentFilter().accepts(entry) else { return }

        DispatchQueue.main.async {
            self.appendToConsole(entry)
            self.lineCount += 1
            if self.isSaving, let handle = self.saveHandle {
                let save = ESPLogParser.saveLine(entry: entry) + "\n"
                if let data = save.data(using: .utf8) {
                    handle.write(data)
                }
            }
        }
    }

    // MARK: - 保存 / 回放

    func toggleSaving() {
        if isSaving {
            stopSaving()
        } else {
            startSaving()
        }
    }

    private func startSaving() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "esp_log_\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")).txt"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            self.saveHandle = handle
            self.isSaving = true
            self.savePath = url.path
            self.statusText = "正在保存日志到 \(url.path)"
        }
    }

    private func stopSaving() {
        saveHandle?.closeFile()
        saveHandle = nil
        isSaving = false
        savePath = nil
        if isConnected {
            statusText = "已连接（只读，不复位）"
        }
    }

    func replayFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer: [String] = []
                for rawLine in content.components(separatedBy: "\n") {
                    let line = rawLine.replacingOccurrences(of: "\r", with: "")
                    guard !line.isEmpty else { continue }
                    let rest = line.components(separatedBy: "\t").dropFirst().joined(separator: "\t")
                    let entry = ESPLogEntry(
                        timestamp: "",
                        raw: rest,
                        level: nil,
                        tag: nil,
                        message: nil
                    )
                    let display = ESPLogParser.displayText(entry: entry)
                    let parsed = ESPLogParser.parse(line: rest)
                    buffer.append(display)
                    DispatchQueue.main.async {
                        self.console.appendLine(display, color: parsed?.level.color)
                        self.lineCount += 1
                    }
                }
            }
        }
    }
}

/// 主界面
struct ContentView: View {
    @StateObject private var viewModel = LogViewModel()

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            filterBar
            Divider()
            LogTextView { textView in
                viewModel.console.attach(textView)
            }
            Divider()
            statusBar
        }
        .padding(8)
        .frame(minWidth: 860, minHeight: 520)
        .onAppear {
            viewModel.refreshPorts()
        }
        .onChange(of: viewModel.tagFilter) { _, _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.minLevel) { _, _ in
            viewModel.applyFilter()
        }
    }

    // MARK: - 连接栏

    private var connectionBar: some View {
        HStack(spacing: 10) {
            Text("串口:")
            Picker("", selection: $viewModel.selectedPort) {
                Text("未选择").tag(String?.none)
                ForEach(viewModel.ports) { port in
                    Text(port.path + (port.isLikelyESP ? "  (ESP32 候选)" : ""))
                        .tag(Optional(port.path))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 260)

            Button("刷新") {
                viewModel.refreshPorts()
            }

            Text("波特率:")
            Picker("", selection: $viewModel.baud) {
                ForEach([9600, 57600, 115200, 230400, 460800, 921600], id: \.self) { b in
                    Text("\(b)").tag(b)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Spacer()

            Button(viewModel.isConnected ? "断开" : "连接") {
                viewModel.toggleConnect()
            }
            .disabled(viewModel.selectedPort == nil)
        }
    }

    // MARK: - 过滤栏

    private var filterBar: some View {
        HStack(spacing: 10) {
            Text("Tag:")
            TextField("如 wifi / app_main（留空不过滤）", text: $viewModel.tagFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Text("最低级别:")
            Picker("", selection: $viewModel.minLevel) {
                Text("全部").tag(LogLevel?.none)
                ForEach(LogLevel.allCases.reversed(), id: \.self) { level in
                    Text("\(level.displayName) [\(level.rawValue)]").tag(LogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            Button("清空") {
                viewModel.console.clear()
                viewModel.lineCount = 0
                viewModel.clearHistory()
            }

            Button(viewModel.isSaving ? "停止保存" : "保存到文件…") {
                viewModel.toggleSaving()
            }
            .disabled(!viewModel.isConnected)

            Button("回放日志…") {
                viewModel.replayFile()
            }
        }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !viewModel.filterSummary.isEmpty {
                Text("过滤中: \(viewModel.filterSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("行数: \(viewModel.lineCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
