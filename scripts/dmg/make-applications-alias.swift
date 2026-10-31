#!/usr/bin/env swift
// DMG에 넣을 Applications 별칭을 만든다. 심볼릭 링크에는 커스텀 아이콘을 붙일 수 없어(리소스 포크 쓰기가 EPERM) 별칭을 쓴다.
// 사용:  swift scripts/dmg/make-applications-alias.swift <만들 경로> <icns 경로>
// 별칭은 만든 Mac의 볼륨 이름·UUID를 담지만, 둘을 바꿔도 /Applications로 풀리는 것을 확인했다.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[2]) else {
    fatalError("usage: make-applications-alias.swift <alias path> <icns path>")
}
let alias = URL(fileURLWithPath: args[1])
let target = URL(fileURLWithPath: "/Applications")
let data = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
try URL.writeBookmarkData(data, to: alias)
guard NSWorkspace.shared.setIcon(icon, forFile: alias.path, options: []) else { fatalError("별칭 아이콘 설정 실패") }
guard try URL(resolvingAliasFileAt: alias, options: [.withoutUI, .withoutMounting]).path == target.path else {
    fatalError("별칭이 /Applications로 풀리지 않음")
}
print("wrote \(alias.path)")
