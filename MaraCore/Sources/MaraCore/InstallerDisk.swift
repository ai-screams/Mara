import Foundation

/// 설치에 쓴 DMG를 꺼낼지 물을지의 순수 판단. 볼륨 열거와 꺼내기는 App이 맡는다.
public enum InstallerDisk {
    public struct Volume: Equatable, Sendable {
        public let name: String
        public let path: String
        public let isReadOnly: Bool
        public let isDiskImage: Bool

        public init(name: String, path: String, isReadOnly: Bool, isDiskImage: Bool) {
            self.name = name
            self.path = path
            self.isReadOnly = isReadOnly
            self.isDiskImage = isDiskImage
        }
    }

    /// release.sh의 `--volname`과 같아야 한다.
    static let volumeName = "Mara"

    /// 꺼내도 되는 설치 디스크. 앱이 그 디스크 안에서 실행 중이면 꺼낼 수 없으므로 고르지 않는다.
    public static func volumeToEject(appPath: String, volumes: [Volume]) -> Volume? {
        volumes.first { volume in
            volume.name == volumeName && volume.isReadOnly && volume.isDiskImage
                && appPath != volume.path && !appPath.hasPrefix(volume.path + "/")
        }
    }
}
