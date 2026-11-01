import XCTest
@testable import DuoBuilder

/// The process group behind Cancel, and how the repo is recognised.
final class DriverTests: XCTestCase {
    func testRepoLookupNeedsTheWrapperAndThePipeline() {
        XCTAssertFalse(Pipeline.isRoot("/tmp"))
        XCTAssertFalse(Pipeline.isRoot(""))
    }

    func testTheWrapperRunsOnTheSystemPython() {
        // never `env python3`: a PATH whose python3 lacks the modules started the old app's builds wrong
        XCTAssertEqual(Pipeline.python, "/usr/bin/python3")
        XCTAssertEqual(Pipeline.duo("/repo", ["info"]), ["/repo/bin/duo", "info"])
    }


    // MARK: The process group

    func testReadsEveryLineAndTheExitCode() throws {
        let done = expectation(description: "exit")
        let collected = LineSink()
        let runner = try ProcessRunner(executable: "/bin/sh",
                                       arguments: ["-c", "echo one; echo two; echo oops >&2; exit 3"],
                                       directory: nil, environment: [:],
                                       onLine: { line, isStdout in collected.add((isStdout ? "out:" : "err:") + line) },
                                       onExit: { code in
                                           XCTAssertEqual(code, 3)
                                           done.fulfill()
                                       })
        withExtendedLifetime(runner) {
            wait(for: [done], timeout: 20)
        }
        XCTAssertEqual(Set(collected.lines), ["out:one", "out:two", "err:oops"])
    }

    /// Cancel must stop what the wrapper started, not only the wrapper: the shell here waits on a child that
    /// outlives a naive `terminate()`.
    func testCancelStopsTheWholeProcessGroup() throws {
        let done = expectation(description: "exit")
        let start = Date()
        var exitCode: Int32 = 0
        let runner = try ProcessRunner(executable: "/bin/sh",
                                       arguments: ["-c", "sleep 60 & echo started; wait"],
                                       directory: nil, environment: [:],
                                       onLine: { _, _ in },
                                       onExit: { code in
                                           exitCode = code
                                           done.fulfill()
                                       })
        withExtendedLifetime(runner) {
            Thread.sleep(forTimeInterval: 0.5)
            runner.cancel()
            wait(for: [done], timeout: 20)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 15, "the group stopped without the SIGKILL fallback")
        XCTAssertNotEqual(exitCode, 0)
    }

    func testLaunchFailureIsReported() {
        XCTAssertThrowsError(try ProcessRunner(executable: "/definitely/not/here", arguments: [], directory: nil,
                                               environment: [:], onLine: { _, _ in }, onExit: { _ in }))
    }
}

/// The lines a background callback collects, read after the expectation.
private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func add(_ line: String) {
        lock.lock(); storage.append(line); lock.unlock()
    }

    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
