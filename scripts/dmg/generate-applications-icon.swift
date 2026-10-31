#!/usr/bin/env swift
// DMG의 Applications 아이콘 생성기 — 마계의 문. 뿔 달린 아치의 쌍문이 조금 열려 있고 틈 뒤로 소용돌이가 보인다.
// 왼쪽의 Mara 눈이 화살표를 따라 이 문으로 들어가는 구도라 가운데는 비워 둔다.
// 사용:  swift scripts/dmg/generate-applications-icon.swift
// 산출:  scripts/dmg/applications.icns (16–1024px)
import AppKit

let accent = NSColor(red: 1, green: 0x95 / 255, blue: 0, alpha: 1)
let ember = NSColor(red: 0.62, green: 0.16, blue: 0.03, alpha: 1)
let stoneHi = NSColor(red: 0.27, green: 0.26, blue: 0.29, alpha: 1)
let stoneLo = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
let stone = NSGradient(starting: stoneHi, ending: stoneLo)!

/// 뾰족 아치. 그림 좌표는 1024 정사각형, 원점은 왼쪽 아래.
func gothicArch(centerX cx: CGFloat, bottom: CGFloat, shoulder: CGFloat, top: CGFloat, halfWidth hw: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx - hw, y: bottom))
    path.line(to: NSPoint(x: cx - hw, y: shoulder))
    path.curve(to: NSPoint(x: cx, y: top),
               controlPoint1: NSPoint(x: cx - hw, y: shoulder + (top - shoulder) * 0.55),
               controlPoint2: NSPoint(x: cx - hw * 0.32, y: top - (top - shoulder) * 0.16))
    path.curve(to: NSPoint(x: cx + hw, y: shoulder),
               controlPoint1: NSPoint(x: cx + hw * 0.32, y: top - (top - shoulder) * 0.16),
               controlPoint2: NSPoint(x: cx + hw, y: shoulder + (top - shoulder) * 0.55))
    path.line(to: NSPoint(x: cx + hw, y: bottom))
    path.close()
    return path
}

func horn(centerX cx: CGFloat, side s: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx + s * 92, y: 690))
    path.curve(to: NSPoint(x: cx + s * 355, y: 958),
               controlPoint1: NSPoint(x: cx + s * 225, y: 742), controlPoint2: NSPoint(x: cx + s * 346, y: 835))
    path.curve(to: NSPoint(x: cx + s * 205, y: 590),
               controlPoint1: NSPoint(x: cx + s * 415, y: 815), controlPoint2: NSPoint(x: cx + s * 345, y: 668))
    path.close()
    return path
}

func drawVortex(center: NSPoint) {
    NSGradient(colors: [ember, NSColor(calibratedWhite: 0.02, alpha: 1)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 400, options: [])
    let rings: [(radius: CGFloat, alpha: CGFloat, width: CGFloat)] = [(350, 0.45, 20), (280, 0.65, 22), (212, 0.85, 24), (146, 1, 26)]
    for ring in rings {
        let path = NSBezierPath(ovalIn: NSRect(x: center.x - ring.radius * 0.4, y: center.y - ring.radius,
                                               width: ring.radius * 0.8, height: ring.radius * 2))
        accent.withAlphaComponent(ring.alpha).setStroke()
        path.lineWidth = ring.width
        path.stroke()
    }
    // 가운데는 비어 있는 어둠 — 눈이 들어갈 자리.
    NSGradient(colors: [.black, .black, NSColor.black.withAlphaComponent(0)], atLocations: [0, 0.6, 1], colorSpace: .deviceRGB)!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 100, options: [])
}

func drawDoorLeaf(centerX cx: CGFloat, side s: CGFloat) {
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: cx + s * 235, y: 112))
    leaf.line(to: NSPoint(x: cx + s * 92, y: 158))
    leaf.line(to: NSPoint(x: cx + s * 92, y: 805))
    leaf.line(to: NSPoint(x: cx + s * 235, y: 860))
    leaf.close()
    NSGradient(starting: NSColor(calibratedWhite: 0.05, alpha: 1), ending: NSColor(calibratedWhite: 0.20, alpha: 1))!
        .draw(in: leaf, angle: s > 0 ? 0 : 180)
    NSColor(calibratedWhite: 0.30, alpha: 1).setStroke()
    for y: CGFloat in [300, 560] {
        let band = NSBezierPath()
        band.move(to: NSPoint(x: cx + s * 92, y: y))
        band.line(to: NSPoint(x: cx + s * 235, y: y - 14))
        band.lineWidth = 12
        band.stroke()
    }
    accent.setStroke()
    let edge = NSBezierPath()
    edge.move(to: NSPoint(x: cx + s * 92, y: 158))
    edge.line(to: NSPoint(x: cx + s * 92, y: 805))
    edge.lineWidth = 10
    edge.stroke()
}

func drawGate() {
    let cx: CGFloat = 512
    let glow = NSPoint(x: cx, y: 470)
    NSGradient(colors: [accent.withAlphaComponent(0.30), accent.withAlphaComponent(0.105), accent.withAlphaComponent(0)],
               atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
        .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: 500, options: [])
    for side: CGFloat in [-1, 1] { stone.draw(in: horn(centerX: cx, side: side), angle: -90) }
    stone.draw(in: gothicArch(centerX: cx, bottom: 112, shoulder: 520, top: 925, halfWidth: 315), angle: -90)
    let opening = gothicArch(centerX: cx, bottom: 112, shoulder: 500, top: 815, halfWidth: 235)
    NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
    opening.fill()
    NSGraphicsContext.saveGraphicsState()
    opening.addClip()
    drawVortex(center: NSPoint(x: cx, y: 400))
    for side: CGFloat in [-1, 1] { drawDoorLeaf(centerX: cx, side: side) }
    NSGraphicsContext.restoreGraphicsState()
    accent.withAlphaComponent(0.85).setStroke()
    opening.lineWidth = 10
    opening.stroke()
    stone.draw(in: NSBezierPath(roundedRect: NSRect(x: cx - 365, y: 70, width: 730, height: 46), xRadius: 8, yRadius: 8), angle: -90)
}

func renderPNG(pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawGate()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
    try data.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("applications.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                       ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                       ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try renderPNG(pixels: pixels, to: iconset.appendingPathComponent("\(name).png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("applications.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil 실패") }
print("wrote \(outDir.appendingPathComponent("applications.icns").path)")
