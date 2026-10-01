#!/usr/bin/env swift
// Mara DMG 창 배경 생성기 — Night Watch 스타일 (Settings 창·랜딩 페이지와 동일 팔레트).
// 사용:  swift scripts/dmg/generate-background.swift
// 산출:  scripts/dmg/background.png (540×380), background@2x.png (1080×760)
// 좌표 계약: release.sh의 create-dmg와 일치해야 한다 — window 540×380, icon 100, text-size 16,
//            앱 아이콘 중심 (140,200), Applications 드롭링크 중심 (400,200) [좌상단 원점].
import AppKit

let W: CGFloat = 540, H: CGFloat = 380
let bg     = NSColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255, alpha: 1)
let accent = NSColor(red: 0xFF / 255, green: 0x95 / 255, blue: 0x00 / 255, alpha: 1)
let muted  = NSColor(red: 0x8B / 255, green: 0x8B / 255, blue: 0x95 / 255, alpha: 1)

// create-dmg의 아이콘 y=200은 좌상단 원점 → AppKit(좌하단 원점) y = H-200.
let iconRowY: CGFloat = H - 200

// 아이콘 이름("Mara"·"Applications")은 배경이 아니라 Finder가 그리고, 색은 시스템이 정한다(DMG에서 지정 불가).
// 라이트 모드와 10.13(다크 모드 없음)은 검은 글자라 어두운 배경에서 사라진다 → 이름 자리에 주황 태그를 깐다.
// 검은 글자 약 6.6:1, 다크 모드의 흰 글자 약 3.2:1. 이름 중심은 좌상단 원점 y≈268(아이콘 아래),
// 크기는 release.sh의 --text-size와 같아야 태그가 이름을 감싼다.
let labelSize: CGFloat = 16
let labelCenterY: CGFloat = H - 268
let labelTag = accent.withAlphaComponent(0.8)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let desc = base.fontDescriptor.withDesign(.rounded),
          let font = NSFont(descriptor: desc, size: size) else { return base }
    return font
}

func drawCentered(_ s: String, font: NSFont, color: NSColor, kern: CGFloat, centerY: CGFloat) {
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    var size = str.size()
    size.width -= kern   // 마지막 글자 뒤 kern 보정(시각 중앙 정렬)
    str.draw(at: NSPoint(x: (W - size.width) / 2, y: centerY - size.height / 2))
}

func tinted(_ symbol: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let img = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    img.isTemplate = false
    return img
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep 생성 실패") }
    rep.size = NSSize(width: W, height: H)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // 상단 헤더: 은은한 오렌지 글로우 + 눈 + 워드마크 + 태그라인 (Settings 헤더와 동일 문법)
    let glowCenter = NSPoint(x: W / 2, y: H - 56)
    NSGradient(colors: [accent.withAlphaComponent(0.14), accent.withAlphaComponent(0)])?
        .draw(fromCenter: glowCenter, radius: 8, toCenter: glowCenter, radius: 150, options: [])
    if let eye = tinted("eye.fill", pointSize: 24, color: accent) {
        eye.draw(in: NSRect(x: (W - eye.size.width) / 2, y: glowCenter.y - eye.size.height / 2,
                            width: eye.size.width, height: eye.size.height))
    }
    drawCentered("Mara", font: rounded(25, .semibold), color: .white, kern: 6, centerY: H - 98)
    drawCentered("The eye that keeps your Mac awake", font: .systemFont(ofSize: 12),
                 color: muted, kern: 0, centerY: H - 122)

    // 설치 화살표: 앱 아이콘(140)과 Applications(400) 사이, 아이콘 행 중앙 높이
    accent.setStroke()
    let shaft = NSBezierPath()
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 212, y: iconRowY))
    shaft.line(to: NSPoint(x: 316, y: iconRowY))
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 332, y: iconRowY))
    head.line(to: NSPoint(x: 314, y: iconRowY + 9))
    head.line(to: NSPoint(x: 314, y: iconRowY - 9))
    head.close()
    accent.setFill()
    head.fill()

    // Finder 이름 뒤 태그 — 폭은 이름 폭 + 좌우 10pt, 높이 26pt 캡슐. 앱 쪽은 "Mara.app" 폭으로 잡는다:
    // Finder의 "모든 파일 확장자 보기"가 켜져 있으면 숨김 비트와 무관하게 확장자가 보인다(10.13 실기에서 확인).
    labelTag.setFill()
    for (centerX, name) in [(CGFloat(140), "Mara.app"), (CGFloat(400), "Applications")] {
        let w = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: labelSize)]).size().width
        NSBezierPath(roundedRect: NSRect(x: centerX - w / 2 - 10, y: labelCenterY - 13, width: w + 20, height: 26),
                     xRadius: 13, yRadius: 13).fill()
    }

    drawCentered("Drag Mara into Applications", font: .systemFont(ofSize: 12),
                 color: muted, kern: 0, centerY: 46)
    return rep
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let outDir = scriptURL.deletingLastPathComponent()
for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let rep = render(scale: scale)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
    let url = outDir.appendingPathComponent(name)
    try! data.write(to: url)
    print("wrote \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}
