// 앱 아이콘 만들기: swift scripts/make-icns.swift  →  Resources/AppIcon.icns
// 원본이 96px라서 큰 크기는 정수배 픽셀 확대(nearest)로 레트로 느낌을 살립니다.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let res = root.appendingPathComponent("Resources")
let src96 = NSImage(contentsOf: res.appendingPathComponent("windows98-96.png"))!
let src48 = NSImage(contentsOf: res.appendingPathComponent("windows98-48.png"))!

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// 캔버스의 75% 크기로 가운데에 그림
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let side = CGFloat(px) * 0.75
    let rect = NSRect(x: (CGFloat(px) - side) / 2, y: (CGFloat(px) - side) / 2, width: side, height: side)
    let (src, srcPx): (NSImage, CGFloat) = side >= 96 ? (src96, 96) : (src48, 48)
    ctx.imageInterpolation = side > srcPx ? .none : .high
    src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let out = res.appendingPathComponent("AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "만들었어요: \(out.path)" : "iconutil 실패")
