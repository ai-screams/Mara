import AppKit

/// 11 미만(SF Symbol 없음)의 메뉴바 눈 아이콘 — `eye.fill` / `eye.slash.fill`을 NSBezierPath로 직접 그린다.
/// 템플릿 이미지로 만들어 두면 비활성은 메뉴바 톤에 적응하고, 활성은 호출부가 tint를 굽는다(본판과 같은 방식).
///
/// 두 상태 모두 **속이 찬 눈 + 동공 구멍**을 쓴다. 감은 눈은 그 위에 사선을 긋고 사선 둘레를 투명하게 비워
/// (`eye.slash.fill`과 같은 방식) 작은 크기에서도 "눈에 사선"으로 읽힌다 — 외곽선만 그리면 `⊘`처럼 보인다.
enum LegacyStatusIcon {
    static func eye(open: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            NSColor.black.set()
            let eye = rect.insetBy(dx: 1, dy: 2)
            almond(in: eye).fill()

            // 동공 구멍(투명) + 가운데 점: 작은 크기에서도 눈으로 읽힌다.
            context.compositingOperation = .clear
            let iris = NSRect(x: eye.midX - 3, y: eye.midY - 3, width: 6, height: 6)
            NSBezierPath(ovalIn: iris).fill()
            context.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: iris.insetBy(dx: 1.6, dy: 1.6)).fill()

            if !open {
                let start = NSPoint(x: rect.minX + 2.5, y: rect.maxY - 0.5)
                let end = NSPoint(x: rect.maxX - 2.5, y: rect.minY + 0.5)
                // 사선 둘레를 먼저 비워(틈) 눈과 사선이 붙어 보이지 않게 한 뒤 사선을 긋는다.
                context.compositingOperation = .clear
                line(from: start, to: end, width: 3.6).stroke()
                context.compositingOperation = .sourceOver
                line(from: start, to: end, width: 1.5).stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 아몬드형 눈: 양 끝이 뾰족한 위·아래 곡선.
    private static func almond(in r: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let left = NSPoint(x: r.minX, y: r.midY)
        let right = NSPoint(x: r.maxX, y: r.midY)
        path.move(to: left)
        path.curve(to: right,
                   controlPoint1: NSPoint(x: r.minX + r.width * 0.28, y: r.maxY + r.height * 0.32),
                   controlPoint2: NSPoint(x: r.maxX - r.width * 0.28, y: r.maxY + r.height * 0.32))
        path.curve(to: left,
                   controlPoint1: NSPoint(x: r.maxX - r.width * 0.28, y: r.minY - r.height * 0.32),
                   controlPoint2: NSPoint(x: r.minX + r.width * 0.28, y: r.minY - r.height * 0.32))
        path.close()
        return path
    }

    private static func line(from a: NSPoint, to b: NSPoint, width: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = width
        path.lineCapStyle = .round
        return path
    }
}
