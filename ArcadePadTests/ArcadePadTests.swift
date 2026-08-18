import XCTest
@testable import ArcadePad

final class PatternTests: XCTestCase {
    func testToggleStep() {
        var pattern = Pattern(stepCount: 16)
        pattern.toggleStep(padIndex: 0, step: 4)
        XCTAssertTrue(pattern.steps(forPad: 0)[4].isActive)
    }

    func testResize() {
        var kit = Kit(gridSize: .four)
        kit.resizeGrid(to: .sixteen)
        XCTAssertEqual(kit.pads.count, 16)
    }
}
