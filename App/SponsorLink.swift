import AppKit

/// 후원 링크의 단일 출처 — **앱 안에서만** 그렇다. 계정을 바꾸면 리포 안 네 곳을 모두 고쳐야 한다:
///   1. 이 파일(`urlString`)
///   2. `README.md` — 상단 배지 + "## Support" 섹션 (URL이 각각 2번씩, 총 4회)
///   3. `docs/index.html` — GitHub Pages 랜딩의 donate 버튼 (2회)
///   4. `.github/FUNDING.yml` — 전체 URL이 아니라 핸들(`github:`/`ko_fi:`)
/// 이 파일만 고치면 앱은 맞지만 README·랜딩 페이지는 조용히 404가 된다(자동 검사 없음).
///
/// 앱 내부 한정으로는: 메뉴바 "Support Mara" 서브메뉴와 설정 창 footer가 모두 `allCases`를
/// 렌더하므로, 후원처 추가·순서 변경은 이 파일만 고치면 두 표면에 동시에 반영된다
/// (표시 순서 = `allCases` 선언 순서).
enum SponsorLink: CaseIterable {
    case githubSponsors
    case koFi

    /// 두 표면의 진입점(서브메뉴 부모 / 드롭다운 라벨)이 공유하는 심볼.
    /// 자식 항목 심볼과 겹치지 않게 외곽선 하트를 쓴다 — `Icon Color`가 `paintpalette`(카테고리)를
    /// 쓰고 자식이 색 스와치를 쓰는 것과 같은 규칙. 라벨 문구는 표면마다 달라서
    /// ("Support Mara" / "Support") 각 호출부가 들고 있다.
    static let containerSymbol = "heart"

    /// 표시명 — UI 문자열은 영어(프로젝트 규칙).
    var title: String {
        switch self {
        case .githubSponsors: return "GitHub Sponsors"
        case .koFi:           return "Ko-fi"
        }
    }

    /// 메뉴 항목·설정 행 선두의 SF Symbol.
    var symbol: String {
        switch self {
        case .githubSponsors: return "heart.fill"
        case .koFi:           return "cup.and.saucer.fill"
        }
    }

    private var urlString: String {
        switch self {
        case .githubSponsors: return "https://github.com/sponsors/ai-screams"
        case .koFi:           return "https://ko-fi.com/pignuante"
        }
    }

    /// 기본 브라우저로 연다. 리터럴 URL이라 파싱은 실패할 수 없지만, 강제 언랩 대신
    /// 조용히 무시한다(심볼 로딩과 같은 방어적 스타일).
    @MainActor
    func open() {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
