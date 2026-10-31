import XCTest
@testable import MaraCore

final class InstallerDiskTests: XCTestCase {
    private let installed = "/Applications/Mara.app"

    private func volume(name: String = "Mara", path: String = "/Volumes/Mara",
                        isReadOnly: Bool = true, isDiskImage: Bool = true) -> InstallerDisk.Volume {
        InstallerDisk.Volume(name: name, path: path, isReadOnly: isReadOnly, isDiskImage: isDiskImage)
    }

    func test_picksTheMountedInstaller() {
        let disk = volume()
        XCTAssertEqual(InstallerDisk.volumeToEject(appPath: installed, volumes: [volume(name: "Backup"), disk]), disk)
    }

    func test_noInstaller_returnsNil() {
        XCTAssertNil(InstallerDisk.volumeToEject(appPath: installed, volumes: []))
    }

    // 이것을 실패시키는 것: 이름 조건을 빼는 것(다른 디스크 이미지를 꺼내자고 묻는다).
    func test_otherDiskImage_isIgnored() {
        XCTAssertNil(InstallerDisk.volumeToEject(appPath: installed, volumes: [volume(name: "Xcode")]))
    }

    // 이것을 실패시키는 것: `isReadOnly` 조건을 빼는 것(사용자가 만든 쓰기 가능한 볼륨을 꺼내자고 묻는다).
    func test_writableVolume_isIgnored() {
        XCTAssertNil(InstallerDisk.volumeToEject(appPath: installed, volumes: [volume(isReadOnly: false)]))
    }

    // 이것을 실패시키는 것: `isDiskImage` 조건을 빼는 것(같은 이름의 실제 디스크를 꺼내자고 묻는다).
    func test_physicalVolume_isIgnored() {
        XCTAssertNil(InstallerDisk.volumeToEject(appPath: installed, volumes: [volume(isDiskImage: false)]))
    }

    // 이것을 실패시키는 것: `hasPrefix` 조건을 빼는 것(실행 중인 자기 디스크를 꺼내려 한다).
    func test_appRunningFromTheDisk_isIgnored() {
        XCTAssertNil(InstallerDisk.volumeToEject(appPath: "/Volumes/Mara/Mara.app", volumes: [volume()]))
    }

    // 이것을 실패시키는 것: 접두어 비교의 "/"를 빼는 것("Mara 1" 안의 앱을 "Mara" 안으로 오판한다).
    func test_appOnSimilarlyNamedVolume_stillPicksTheInstaller() {
        let disk = volume()
        XCTAssertEqual(InstallerDisk.volumeToEject(appPath: "/Volumes/Mara 1/Mara.app", volumes: [disk]), disk)
    }
}
