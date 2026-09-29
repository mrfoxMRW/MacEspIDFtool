import Foundation
import Darwin

// 串口相关错误
enum SerialError: LocalizedError {
    case openFailed(path: String, reason: String)
    case configFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let reason):
            return "无法打开串口 \(path): \(reason)"
        case .configFailed(let path, let reason):
            return "串口配置失败 \(path): \(reason)"
        case .readFailed(let path, let reason):
            return "读取串口失败 \(path): \(reason)"
        }
    }
}

// 串口信息（枚举结果）
struct SerialPortInfo: Identifiable, Equatable {
    var id: String { path }
    let path: String

    /// 是否像 ESP32 设备（用于候选标记与自动选择）
    var isLikelyESP: Bool {
        let known = [
            "usbmodem", "wchusbserial", "SLAB_USBtoUART", "esp32",
            "esp32s3", "usbserial", "usb-", "debug-console",
        ]
        return known.contains { path.localizedCaseInsensitiveContains($0) }
    }
}

// 端口枚举：扫描 /dev/cu.*，排除蓝牙等无关设备
enum SerialPortScanner {
    static func detect() -> [SerialPortInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else {
            return []
        }
        let bad = ["Bluetooth", "BT-", "MIPortableSpeaker", "Incoming"]
        return entries
            .filter { $0.hasPrefix("cu.") }
            .filter { path in !bad.contains(where: { path.contains($0) }) }
            .map { SerialPortInfo(path: "/dev/\($0)") }
            .sorted { $0.path < $1.path }
    }
}

/// 零依赖 POSIX 串口封装（只读语义：打开后清除 DTR/RTS，绝不触发芯片复位）
final class SerialPort {
    private(set) var fd: Int32 = -1
    let path: String
    let baud: Int

    var isOpen: Bool { fd >= 0 }

    init(path: String, baud: Int) {
        self.path = path
        self.baud = baud
    }

    deinit {
        close()
    }

    func open() throws {
        guard !isOpen else { return }

        let fdValue = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fdValue >= 0 else {
            throw SerialError.openFailed(path: path, reason: String(cString: strerror(errno)))
        }
        fd = fdValue

        var tio = termios()
        guard tcgetattr(fdValue, &tio) == 0 else {
            let reason = String(cString: strerror(errno))
            close()
            throw SerialError.configFailed(path: path, reason: "tcgetattr: \(reason)")
        }

        // 原始模式 + 标准 8N1
        cfmakeraw(&tio)
        let speedType = type(of: tio.c_ospeed)
        tio.c_ospeed = speedType.init(baud)
        tio.c_ispeed = speedType.init(baud)
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD)

        guard tcsetattr(fdValue, TCSANOW, &tio) == 0 else {
            let reason = String(cString: strerror(errno))
            close()
            throw SerialError.configFailed(path: path, reason: "tcsetattr: \(reason)")
        }

        // 关键：清除 DTR/RTS，防止 ESP32 进入下载/复位状态（只读铁律）
        var clearBits: Int32 = TIOCM_DTR | TIOCM_RTS
        guard ioctl(fdValue, TIOCMBIC, &clearBits) == 0 else {
            let reason = String(cString: strerror(errno))
            close()
            throw SerialError.configFailed(path: path, reason: "清除 DTR/RTS 失败: \(reason)")
        }
    }

    func close() {
        guard isOpen else { return }
        Darwin.close(fd)
        fd = -1
    }

    /// 阻塞读取一块数据（带超时，避免忙轮询）。超时返回空数组。
    func readChunk(timeoutMs: Int = 200) throws -> [UInt8] {
        guard isOpen else { return [] }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollResult = poll(&pfd, 1, Int32(timeoutMs))
        if pollResult == 0 {
            return [] // 超时，无数据
        }
        if pollResult < 0 {
            if errno == EINTR { return [] }
            throw SerialError.readFailed(path: path, reason: String(cString: strerror(errno)))
        }

        var buf = [UInt8](repeating: 0, count: 2048)
        let n = read(fd, &buf, buf.count)
        if n < 0 {
            if errno == EAGAIN || errno == EINTR { return [] }
            throw SerialError.readFailed(path: path, reason: String(cString: strerror(errno)))
        }
        if n == 0 { return [] }
        return Array(buf.prefix(n))
    }
}