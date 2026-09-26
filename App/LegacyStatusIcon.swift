import AppKit

/// 11 미만(SF Symbol 없음)의 메뉴바 눈 아이콘 — `eye.fill` / `eye.slash.fill`을 NSBezierPath로 직접 그린다.
/// 템플릿 이미지로 만들어 두면 비활성은 메뉴바 톤에 적응하고, 활성은 호출부가 tint를 굽는다(본판과 같은 방식).
enum LegacyStatusIcon {
    static func eye(open: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            let inset = rect.insetBy(dx: 1, dy: 1)
            // 아몬드형 눈: 위·아래 두 곡선.
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: inset.minX, y: inset.midY))
            outline.curve(to: NSPoint(x: inset.maxX, y: inset.midY),
                          controlPoint1: NSPoint(x: inset.minX + inset.width * 0.25, y: inset.maxY + 1),
                          controlPoint2: NSPoint(x: inset.maxX - inset.width * 0.25, y: inset.maxY + 1))
            outline.curve(to: NSPoint(x: inset.minX, y: inset.midY),
                          controlPoint1: NSPoint(x: inset.maxX - inset.width * 0.25, y: inset.minY - 1),
                          controlPoint2: NSPoint(x: inset.minX + inset.width * 0.25, y: inset.minY - 1))
            outline.close()
            if open {
                outline.fill()
                // 동공 자리를 비워(투명) 뜬 눈으로 보이게 한다.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: inset.midX - 2.5, y: inset.midY - 2.5, width: 5, height: 5)).fill()
            } else {
                outline.lineWidth = 1.4
                outline.stroke()
                // 감은 눈: 대각선 한 줄(eye.slash).
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: rect.minX + 2, y: rect.minY))
                slash.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY))
                slash.lineWidth = 1.6
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
