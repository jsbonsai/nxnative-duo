import XCTest
@testable import DuoBuilder

/// The `--progress json` lines of docs/frontends.md, read leniently: one field of a stage may be missing and the
/// reader still follows the build; a line that is not an event is left to the log.
final class ProgressEventTests: XCTestCase {
    func testStage() {
        let event = ProgressEvent.parse(#"{"ev": "stage", "k": 3, "n": 9, "name": "iOS shaders", "step": "starting", "t": 1.0}"#)
        XCTAssertEqual(event?.ev, .stage)
        XCTAssertEqual(event?.k, 3)
        XCTAssertEqual(event?.n, 9)
        XCTAssertEqual(event?.name, "iOS shaders")
        XCTAssertEqual(event?.step, "starting")
    }

    func testStep() {
        let event = ProgressEvent.parse(#"{"ev": "step", "k": 1, "name": "extract base", "step": "reading the NCA headers"}"#)
        XCTAssertEqual(event?.ev, .step)
        XCTAssertEqual(event?.step, "reading the NCA headers")
    }

    /// done/total arrive as JSON integers; frac and eta may be null.
    func testProgress() {
        let line = #"{"ev": "progress", "k": 2, "name": "iOS shaders", "step": "translating", "done": 1203, "total": 19592, "unit": "shaders", "est": true, "note": "", "frac": 0.0614, "eta": 840.5, "elapsed": 12.25}"#
        let event = ProgressEvent.parse(line)
        XCTAssertEqual(event?.ev, .progress)
        XCTAssertEqual(event?.done, 1203)
        XCTAssertEqual(event?.total, 19592)
        XCTAssertEqual(event?.unit, "shaders")
        XCTAssertEqual(event?.est, true)
        XCTAssertEqual(event?.frac, 0.0614)
        XCTAssertEqual(event?.eta, 840.5)
        XCTAssertEqual(event?.elapsed, 12.25)
    }

    func testProgressWithNulls() {
        let line = #"{"ev": "progress", "k": 1, "name": "extract base", "step": "", "done": 0, "total": null, "unit": "", "est": false, "note": "", "frac": null, "eta": null, "elapsed": 0.5}"#
        let event = ProgressEvent.parse(line)
        XCTAssertEqual(event?.ev, .progress)
        XCTAssertNil(event?.frac)
        XCTAssertNil(event?.eta)
    }

    func testStageEnd() {
        let event = ProgressEvent.parse(#"{"ev": "stage_end", "k": 2, "name": "iOS shaders", "ok": false, "summary": "3 failed", "elapsed": 903.0}"#)
        XCTAssertEqual(event?.ev, .stageEnd)
        XCTAssertEqual(event?.ok, false)
        XCTAssertEqual(event?.summary, "3 failed")
    }

    func testSay() {
        let event = ProgressEvent.parse(#"{"ev": "say", "msg": "[RED] no such file: /x", "t": 4.0}"#)
        XCTAssertEqual(event?.ev, .say)
        XCTAssertEqual(event?.msg, "[RED] no such file: /x")
    }

    /// bin/duo's own messages and anything else on the stream are not events.
    func testNonEventsAreIgnored() {
        XCTAssertNil(ProgressEvent.parse("Building Wonder — mode letterbox — this is the long step (shaders)."))
        XCTAssertNil(ProgressEvent.parse(""))
        XCTAssertNil(ProgressEvent.parse("{\"ev\": \"stage\""))
        XCTAssertNil(ProgressEvent.parse(#"{"ev": "something_new"}"#))
    }

    func testCountsAndDurations() {
        XCTAssertEqual(StageCopy.count(done: 1.9e9, total: 5.0e9, unit: "B", estimate: true), "1.8 GB of ~4.7 GB")
        XCTAssertEqual(StageCopy.count(done: 1203, total: 19592, unit: "shaders", estimate: true), "1,203 of ~19,592 shaders")
        XCTAssertEqual(StageCopy.count(done: 2301, total: 0, unit: "files", estimate: false), "2,301 files")
        XCTAssertEqual(StageCopy.count(done: 0, total: 0, unit: "", estimate: false), "")
        XCTAssertEqual(StageCopy.duration(38), "38s")
        XCTAssertEqual(StageCopy.duration(252), "4m 12s")
        XCTAssertEqual(StageCopy.duration(3780), "1h 03m")
    }

    func testPlainLanguageHeadlines() {
        XCTAssertEqual(StageCopy.headline(for: "iOS shaders"), StageCopy.headline(for: "shader split"))
        XCTAssertTrue(StageCopy.headline(for: "iOS shaders")!.contains("Compiling shaders"))
        XCTAssertTrue(StageCopy.headline(for: "extract base")!.contains("Reading the game"))
        XCTAssertTrue(StageCopy.headline(for: "rewrite")!.contains("executable"))
        XCTAssertNil(StageCopy.headline(for: "some new stage"))
    }
}
