import XCTest
@testable import Shotmori

/// Kurulum v2 görselleri: dört dil-nötr örnek kart, hepsi farklı; gövde metinleri tek cümle.
final class OnboardingVisualsTests: XCTestCase {
    func testSampleKindsCoverFourCards() {
        XCTAssertEqual(SampleShelfPreview.kinds.count, 4)
        XCTAssertEqual(Set(SampleShelfPreview.kinds).count, 4)
    }
    func testBodyTextsAreSingleSentences() {
        for t in [S.obWelcomeBody, S.obAccumulateBody, S.obHotKeyBody, S.obTryBody, S.obDragBody] {
            XCTAssertLessThanOrEqual(t.filter { $0 == "." }.count, 1, t)
        }
    }
}
