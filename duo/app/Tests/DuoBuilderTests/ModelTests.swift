import XCTest
@testable import DuoBuilder

/// What the app reads from bin/duo, and the one piece of arithmetic it owns (the progress bar).
final class ModelTests: XCTestCase {
    func testGameInfoDecodesTheWrapperOutput() throws {
        // abridged from a real `duo info --json` of DRAGON QUEST VII Reimagined (base + 1.1.0 + 1.2.0)
        let json = """
        {"game": {"title": "0100a9d01c446000", "name": "DRAGON QUEST VII Reimagined", "publisher": "SQUARE ENIX CO., LTD.",
          "version": "1.2.0", "icon": "/tmp/i.jpg", "build_id": "f7ec03e4cb9de3bd8319d4e899d2e9cc", "bytes": 4999999999},
         "base": {"kind": "application", "title": "0100a9d01c446000", "version": 0, "name": "x", "display_version": "1.0.0",
          "file": "/g/base.nsp", "bytes": 1, "main_build_id": "ab06"},
         "update": {"kind": "patch", "display_version": "1.2.0", "file": "/g/u12.nsp"},
         "updates": [{"kind": "patch", "display_version": "1.1.0", "file": "/g/u11.nsp"},
                     {"kind": "patch", "display_version": "1.2.0", "file": "/g/u12.nsp"}],
         "dlc": [], "duo": {"state": "available", "name": "TotK camera", "author": "a"}, "problems": [], "keys": "/k/prod.keys"}
        """
        let info = try XCTUnwrap(Pipeline.decode(GameInfo.self, json))
        XCTAssertEqual(info.game?.version, "1.2.0")
        XCTAssertEqual(info.game?.buildId, "f7ec03e4cb9de3bd8319d4e899d2e9cc")
        XCTAssertEqual(info.duo.state, "available"); XCTAssertEqual(info.duo.name, "TotK camera")
        XCTAssertEqual(info.files, ["/g/base.nsp", "/g/u11.nsp", "/g/u12.nsp"], "every package is passed on, base first")
    }

    func testAnUpdateWithoutItsGameIsAProblemNotACrash() throws {
        let json = """
        {"game": {"title": "0100a9d01c446000", "name": "DQ"}, "base": null, "update": {"kind": "patch", "file": "/u.nsp"},
         "updates": [{"kind": "patch", "file": "/u.nsp"}], "dlc": [], "duo": {"state": "none"},
         "problems": ["no base game yet: add the game itself (.nsp or .xci), not only its update"], "keys": null}
        """
        let info = try XCTUnwrap(Pipeline.decode(GameInfo.self, json))
        XCTAssertNil(info.base)
        XCTAssertEqual(info.problems.count, 1)
    }

    func testDoctorDecodesAndCountsWhatIsMissing() throws {
        let json = """
        {"items": [{"id": "xcode", "title": "Xcode", "ok": true, "detail": "installed", "fix": "manual", "action": "x"},
                   {"id": "python", "title": "Python", "ok": false, "detail": "missing", "fix": "auto", "action": ""},
                   {"id": "account", "title": "Apple ID", "ok": false, "detail": "sign in", "fix": "manual", "action": "xcode-accounts"}],
         "ready": false}
        """
        let d = try XCTUnwrap(Pipeline.decode(Doctor.self, json))
        XCTAssertFalse(d.ready)
        XCTAssertEqual(d.missing.map(\.id), ["python", "account"])
    }

    func testDecodeSkipsLinesBeforeTheJSON() {
        // the wrapper may print a warning line before its JSON (a tool's own stderr merged in)
        XCTAssertNotNil(Pipeline.decode(Doctor.self, "warning: x\n{\"items\": [], \"ready\": true}"))
    }

    func testTheProgressBarCoversTheWholeRangeInOrder() {
        // six wrapper steps: they tile 0…1 with no gap and no overlap, so the bar never jumps back
        var last = 0.0
        for k in 1...6 {
            let s = AppModel.span(k, 6)
            XCTAssertEqual(s.lowerBound, last, accuracy: 1e-9, "step \(k) starts where the previous ended")
            XCTAssertLessThan(s.lowerBound, s.upperBound)
            last = s.upperBound
        }
        XCTAssertEqual(last, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(AppModel.span(2, 6).upperBound - AppModel.span(2, 6).lowerBound, 0.7,
                             "preparing the game (extract, rewrite, shaders) is most of a first install")
    }
}
