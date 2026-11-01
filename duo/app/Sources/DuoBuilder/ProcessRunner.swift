import Foundation

/// A child process in a process group of its own, so Cancel stops the whole build: python, the NSP pipeline and
/// everything the pipeline starts (xcodebuild, codesign, xcrun devicectl). stdout and stderr are read line by
/// line through PipeReader, so a build reports while it runs and nothing is held in a buffer.
final class ProcessRunner {
    struct LaunchError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let out = LineBuffer()
    private let err = LineBuffer()
    private let onLine: (String, Bool) -> Void
    private let onExit: (Int32) -> Void
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var finished = false
    private var outHandle: FileHandle?
    private var errHandle: FileHandle?

    /// `executable` runs with `arguments` in `directory`, with stdout and stderr as pipes. `onLine` gets every
    /// complete line (second argument: true for stdout); `onExit` gets the shell-style exit code once.
    init(executable: String, arguments: [String], directory: String?, environment: [String: String],
         onLine: @escaping (String, Bool) -> Void, onExit: @escaping (Int32) -> Void) throws {
        self.onLine = onLine
        self.onExit = onExit

        var outFD: [Int32] = [-1, -1]
        var errFD: [Int32] = [-1, -1]
        guard pipe(&outFD) == 0 else { throw LaunchError(message: "pipe: \(String(cString: strerror(errno)))") }
        guard pipe(&errFD) == 0 else {
            close(outFD[0]); close(outFD[1])
            throw LaunchError(message: "pipe: \(String(cString: strerror(errno)))")
        }
        defer { close(outFD[1]); close(errFD[1]) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, outFD[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errFD[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, outFD[0])
        posix_spawn_file_actions_addclose(&actions, errFD[0])
        posix_spawn_file_actions_addclose(&actions, outFD[1])
        posix_spawn_file_actions_addclose(&actions, errFD[1])
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory) }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // A group leader of its own: kill(-pid) reaches the pipeline's children too.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var child: pid_t = 0
        let env = environment.map { "\($0.key)=\($0.value)" }.sorted()
        let rc = Self.withCStrings([executable] + arguments) { argv in
            Self.withCStrings(env) { envp in
                posix_spawn(&child, executable, &actions, &attr, argv, envp)
            }
        }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)
        guard rc == 0 else { throw LaunchError(message: "\(executable): \(String(cString: strerror(rc)))") }
        pid = child

        let outHandle = FileHandle(fileDescriptor: outFD[0], closeOnDealloc: true)
        let errHandle = FileHandle(fileDescriptor: errFD[0], closeOnDealloc: true)
        // Held for the runner's lifetime: a FileHandle closes its descriptor when it is deallocated, which would
        // leave the child writing into a closed pipe (SIGPIPE).
        self.outHandle = outHandle
        self.errHandle = errHandle
        PipeReader.attach(to: outHandle) { [weak self] chunk in
            guard let self else { return }
            for line in self.out.append(chunk) { self.onLine(line, true) }
        }
        PipeReader.attach(to: errHandle) { [weak self] chunk in
            guard let self else { return }
            for line in self.err.append(chunk) { self.onLine(line, false) }
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var status: Int32 = 0
            var r: pid_t
            repeat { r = waitpid(child, &status, 0) } while r == -1 && errno == EINTR
            // Everything the child wrote is delivered before onExit: take the pipes back from the readability
            // handlers and read what is left of them.
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            for line in out.append(Self.remaining(outHandle)) { onLine(line, true) }
            for line in err.append(Self.remaining(errHandle)) { onLine(line, false) }
            if let tail = out.drain() { onLine(tail, true) }
            if let tail = err.drain() { onLine(tail, false) }
            let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            lock.lock(); finished = true; lock.unlock()
            onExit(code)
        }
    }

    /// SIGTERM to the process group; SIGKILL five seconds later when anything in it is still running.
    func cancel() {
        lock.lock()
        let group = pid
        let done = finished
        lock.unlock()
        guard group > 0, !done else { return }
        kill(-group, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillRunning = !self.finished
            let group = self.pid
            self.lock.unlock()
            if stillRunning, group > 0 { kill(-group, SIGKILL) }
        }
    }

    /// Whatever the child wrote before exiting and the readability handler has not read yet.
    private static func remaining(_ handle: FileHandle) -> Data {
        do { return try handle.readToEnd() ?? Data() } catch { return Data() }
    }

    private static func withCStrings<T>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> T) -> T {
        var pointers = strings.map { strdup($0) }
        pointers.append(nil)
        defer { for p in pointers where p != nil { free(p) } }
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

/// The lines read so far from one pipe: whole lines go out, the rest waits for the next chunk.
private final class LineBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        var lines: [String] = []
        lock.lock()
        data.append(chunk)
        while let i = data.firstIndex(of: 0x0A) {
            let line = data[data.startIndex..<i]
            data.removeSubrange(data.startIndex...i)
            lines.append(String(decoding: line, as: UTF8.self))
        }
        // A tool that writes a megabyte without a newline gets it as one line rather than as memory.
        if data.count > 1 << 20 {
            lines.append(String(decoding: data, as: UTF8.self))
            data.removeAll()
        }
        lock.unlock()
        return lines
    }

    func drain() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        data.removeAll()
        return text
    }
}
