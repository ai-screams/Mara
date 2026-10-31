import AppKit
import DiskArbitration
import MaraCore

/// 설치에 쓴 DMG가 마운트된 채로 남아 있으면 꺼낼지 묻는다. 고르는 판단은 Core `InstallerDisk`가 맡는다.
/// DMG 파일 삭제는 제안하지 않는다 — Downloads 접근 권한이 필요하다.
@MainActor
enum InstallerEject {
    static func offerIfMounted() {
        guard let volume = InstallerDisk.volumeToEject(appPath: Bundle.main.bundlePath,
                                                       volumes: mountedVolumes()) else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Eject the Mara installer?"
        alert.informativeText = "Mara is installed, so you no longer need the installer disk."
        alert.addButton(withTitle: "Eject")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = URL(fileURLWithPath: volume.path)
        // 꺼내기는 동기 호출이고 디스크를 쓰는 프로세스가 있으면 오래 걸릴 수 있어 메인 밖에서 한다.
        Task.detached(priority: .utility) {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                NSLog("Installer eject failed: \(error)")
            }
        }
    }

    /// 볼륨 속성만 읽는다 — 디스크 안의 파일을 읽으면 이동식 볼륨 접근 권한을 물을 수 있다.
    private static func mountedVolumes() -> [InstallerDisk.Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let name = values.volumeName,
                  let isReadOnly = values.volumeIsReadOnly else { return nil }
            return InstallerDisk.Volume(name: name, path: url.path, isReadOnly: isReadOnly,
                                        isDiskImage: isDiskImage(url))
        }
    }

    private static func isDiskImage(_ url: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        return description[kDADiskDescriptionDeviceModelKey] as? String == "Disk Image"
    }
}
