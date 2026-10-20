import Foundation
import Compression

public struct ZipOptions {
    /// 옛날 윈도우·그룹웨어 호환: 이름을 CP949로 저장하고, UTF-8 이름은 확장 필드(0x7075)에 함께 넣음
    public var legacyCP949: Bool

    public init(legacyCP949: Bool = false) {
        self.legacyCP949 = legacyCP949
    }
}

public struct ZipReport {
    public var output = ""
    public var fileCount = 0
    public var dirCount = 0
    /// 뺀 맥 숨김파일 수
    public var excludedJunk = 0
    /// 뺀 심볼릭 링크
    public var skippedLinks: [String] = []
    /// 윈도우용으로 이름을 바꿔 넣은 수 (자소분리 포함)
    public var renamed = 0

    public init() {}
}

public enum ZipError: LocalizedError {
    case tooLarge
    case tooManyEntries
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "4GB가 넘는 ZIP은 아직 만들 수 없어요."
        case .tooManyEntries: return "파일이 65,535개를 넘으면 아직 만들 수 없어요."
        case .io(let msg): return msg
        }
    }
}

/// 윈도우에서 깨지지 않는 ZIP 만들기. 원본 파일은 건드리지 않습니다.
public enum Zipper {
    struct Item {
        let source: String
        let zipPath: String   // "폴더/파일.txt", 폴더는 끝에 "/"
        let isDir: Bool
        let size: UInt64
        let modified: Date
    }

    /// 이미 압축된 형식은 다시 압축하지 않고 그대로 저장
    static let storedExtensions: Set<String> = [
        "zip", "7z", "rar", "gz", "bz2", "xz", "zst", "dmg", "jpg", "jpeg", "png", "gif", "heic", "webp",
        "mp3", "m4a", "aac", "mp4", "mov", "m4v", "avi", "mkv", "docx", "xlsx", "pptx", "hwpx", "pdf",
    ]

    /// 첫 항목 옆에 "이름.zip" (여러 개면 "보관.zip"). 이미 있으면 "이름 2.zip"
    public static func defaultOutputPath(for paths: [String]) -> String {
        let first = (paths[0] as NSString).standardizingPath
        let dir = (first as NSString).deletingLastPathComponent
        let base = paths.count == 1 ? Rules.sanitize((first as NSString).lastPathComponent).fixed : "보관"
        var candidate = dir + "/" + base + ".zip"
        var n = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = dir + "/" + base + " \(n).zip"
            n += 1
        }
        return candidate
    }

    public static func makeZip(paths: [String], to output: String, options: ZipOptions = ZipOptions(),
                               progress: ((Double) -> Void)? = nil) throws -> ZipReport {
        var report = ZipReport()
        report.output = output
        let items = collect(paths: paths.map { ($0 as NSString).standardizingPath }, report: &report)

        let total = items.reduce(UInt64(0)) { $0 + $1.size }
        if items.contains(where: { $0.size >= 0xFFFF_FFFF }) || total >= 0xF000_0000 { throw ZipError.tooLarge }
        if items.count >= 0xFFFF { throw ZipError.tooManyEntries }

        // 임시 파일에 쓰고 마지막에 이름을 바꿔서, 중간에 실패해도 반쯤 만든 ZIP이 남지 않게 함
        let dir = (output as NSString).deletingLastPathComponent
        let tmp = dir + "/.macwin-" + UUID().uuidString + ".zip"
        let fd = tmp.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o644) }
        guard fd >= 0 else { throw ZipError.io("ZIP 파일을 만들 수 없어요: " + String(cString: strerror(errno))) }
        let out = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var succeeded = false
        defer {
            try? out.close()
            if !succeeded { _ = tmp.withCString { unlink($0) } }
        }

        var central = Data()
        var done: UInt64 = 0
        for item in items {
            let (nameBytes, extra, flags) = encodeName(item.zipPath, legacy: options.legacyCP949)
            let method: UInt16 = item.isDir || storedExtensions.contains((item.zipPath as NSString).pathExtension.lowercased()) ? 0 : 8
            let (time, date) = dosDateTime(item.modified)
            let offset = try out.offset()

            var local = Data()
            local.le32(0x0403_4b50)
            local.le16(20); local.le16(flags); local.le16(method); local.le16(time); local.le16(date)
            local.le32(0); local.le32(0); local.le32(0)   // crc, 압축 크기, 원래 크기: 쓰고 나서 채움
            local.le16(UInt16(nameBytes.count)); local.le16(UInt16(extra.count))
            local.append(nameBytes); local.append(extra)
            try out.write(contentsOf: local)

            var crc: UInt32 = 0, compressed: UInt64 = 0, original: UInt64 = 0
            if !item.isDir {
                (crc, original, compressed) = try writeData(of: item.source, to: out, deflate: method == 8) { n in
                    done += n
                    if total > 0 { progress?(Double(done) / Double(total)) }
                }
                let end = try out.offset()
                try out.seek(toOffset: offset + 14)
                var sizes = Data()
                sizes.le32(crc); sizes.le32(UInt32(compressed)); sizes.le32(UInt32(original))
                try out.write(contentsOf: sizes)
                try out.seek(toOffset: end)
            }
            if try out.offset() >= 0xFFFF_FFFF { throw ZipError.tooLarge }

            // 만든 프로그램 = MS-DOS(0) → 윈도우가 폴더 속성(0x10)을 그대로 이해함
            central.le32(0x0201_4b50)
            central.le16(20); central.le16(20); central.le16(flags); central.le16(method)
            central.le16(time); central.le16(date)
            central.le32(crc); central.le32(UInt32(compressed)); central.le32(UInt32(original))
            central.le16(UInt16(nameBytes.count)); central.le16(UInt16(extra.count)); central.le16(0)
            central.le16(0); central.le16(0)
            central.le32(item.isDir ? 0x10 : 0)
            central.le32(UInt32(offset))
            central.append(nameBytes); central.append(extra)

            if item.isDir { report.dirCount += 1 } else { report.fileCount += 1 }
        }

        let centralOffset = try out.offset()
        try out.write(contentsOf: central)
        var end = Data()
        end.le32(0x0605_4b50)
        end.le16(0); end.le16(0)
        end.le16(UInt16(items.count)); end.le16(UInt16(items.count))
        end.le32(UInt32(central.count)); end.le32(UInt32(centralOffset))
        end.le16(0)
        try out.write(contentsOf: end)
        try out.synchronize()

        let rc = tmp.withCString { a in output.withCString { b in renamex_np(a, b, UInt32(RENAME_EXCL)) } }
        guard rc == 0 else { throw ZipError.io("ZIP 파일 이름을 정할 수 없어요: " + String(cString: strerror(errno))) }
        succeeded = true
        progress?(1)
        return report
    }

    // MARK: - 넣을 항목 모으기

    static func collect(paths: [String], report: inout ZipReport) -> [Item] {
        var items: [Item] = []
        var rootNames = Set<String>()
        for path in Scanner.dedupeRoots(paths) {
            let name = (path as NSString).lastPathComponent
            if Rules.isMacJunk(name) { report.excludedJunk += 1; continue }
            let zipName = uniqueName(for: name, in: &rootNames, report: &report)
            add(path: path, zipPath: zipName, items: &items, report: &report)
        }
        return items
    }

    static func add(path: String, zipPath: String, items: inout [Item], report: inout ZipReport) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        switch st.st_mode & S_IFMT {
        case S_IFLNK:
            report.skippedLinks.append(zipPath)
        case S_IFDIR:
            items.append(Item(source: path, zipPath: zipPath + "/", isDir: true, size: 0, modified: modified))
            var used = Set<String>()
            for child in Scanner.listDir(path) ?? [] {
                if Rules.isMacJunk(child.name) { report.excludedJunk += 1; continue }
                let name = uniqueName(for: child.name, in: &used, report: &report)
                add(path: path + "/" + child.name, zipPath: zipPath + "/" + name, items: &items, report: &report)
            }
        case S_IFREG:
            items.append(Item(source: path, zipPath: zipPath, isDir: false, size: UInt64(st.st_size), modified: modified))
        default:
            break
        }
    }

    /// 윈도우용으로 고친 이름. 같은 폴더에서 겹치면 "이름 (2).확장자"
    static func uniqueName(for name: String, in used: inout Set<String>, report: inout ZipReport) -> String {
        var fixed = Rules.sanitize(name).fixed
        if Rules.windowsKeyTaken(fixed, in: used) {
            let ext = (fixed as NSString).pathExtension
            let stem = ext.isEmpty ? fixed : (fixed as NSString).deletingPathExtension
            var n = 2
            repeat {
                fixed = stem + " (\(n))" + (ext.isEmpty ? "" : "." + ext)
                n += 1
            } while Rules.windowsKeyTaken(fixed, in: used)
        }
        used.insert(Rules.windowsKey(fixed))
        if !Rules.sameScalars(fixed, name) { report.renamed += 1 }
        return fixed
    }

    // MARK: - 이름 인코딩

    static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    /// (헤더에 들어갈 이름 바이트, 확장 필드, 플래그)
    static func encodeName(_ name: String, legacy: Bool) -> (Data, Data, UInt16) {
        let utf8 = Data(name.utf8)
        guard legacy else { return (utf8, Data(), 0x0800) }   // bit 11: 이름이 UTF-8

        // CP949로 못 쓰는 글자(이모지 등)는 _ 로 바꾸고, 원래 이름은 0x7075 필드에 UTF-8로 넣음
        var legacyName = Data()
        for ch in name {
            legacyName.append(String(ch).data(using: cp949) ?? Data("_".utf8))
        }
        var extra = Data()
        extra.le16(0x7075)
        extra.le16(UInt16(5 + utf8.count))
        extra.append(1)
        extra.le32(CRC32.update(0, legacyName))
        extra.append(utf8)
        return (legacyName, extra, 0)
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, c.year ?? 1980))
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }

    // MARK: - 내용 쓰기

    /// (crc, 원래 크기, 저장된 크기)
    static func writeData(of path: String, to out: FileHandle, deflate: Bool,
                          onRead: (UInt64) -> Void) throws -> (UInt32, UInt64, UInt64) {
        let fd = path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else { throw ZipError.io("읽을 수 없어요: \(path)") }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? input.close() }

        var crc: UInt32 = 0, original: UInt64 = 0, written: UInt64 = 0
        let chunkSize = 1 << 20

        guard deflate else {
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                crc = CRC32.update(crc, chunk)
                try out.write(contentsOf: chunk)
                original += UInt64(chunk.count); written += UInt64(chunk.count)
                onRead(UInt64(chunk.count))
            }
            return (crc, original, written)
        }

        // COMPRESSION_ZLIB는 ZIP에 필요한 raw DEFLATE를 만듦
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZipError.io("압축을 시작할 수 없어요")
        }
        defer { compression_stream_destroy(stream) }

        let dstSize = 1 << 16
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }

        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            let finalize = chunk.isEmpty
            crc = CRC32.update(crc, chunk)
            original += UInt64(chunk.count)
            onRead(UInt64(chunk.count))

            var status = COMPRESSION_STATUS_OK
            try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                // 빈 입력일 때도 포인터는 있어야 해서 dst를 대신 넘김 (크기 0이라 읽지 않음)
                stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(dst)
                stream.pointee.src_size = chunk.count
                repeat {
                    stream.pointee.dst_ptr = dst
                    stream.pointee.dst_size = dstSize
                    status = compression_stream_process(stream, finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    guard status != COMPRESSION_STATUS_ERROR else { throw ZipError.io("압축 중 오류가 났어요: \(path)") }
                    let produced = dstSize - stream.pointee.dst_size
                    if produced > 0 {
                        try out.write(contentsOf: Data(bytes: dst, count: produced))
                        written += UInt64(produced)
                    }
                } while status == COMPRESSION_STATUS_OK
                    && (finalize || stream.pointee.src_size > 0 || stream.pointee.dst_size == 0)
            }
            if finalize { break }
        }
        return (crc, original, written)
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        var c = ~crc
        table.withUnsafeBufferPointer { t in
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for b in bytes { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
            }
        }
        return ~c
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
