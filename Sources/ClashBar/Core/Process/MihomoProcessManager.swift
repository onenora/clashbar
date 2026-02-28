import Darwin
import Foundation

// Process callbacks run on system-managed threads. Shared mutable state is guarded by `lock`.
final class MihomoProcessManager: MihomoControlling, @unchecked Sendable {
    private(set) var status: CoreLifecycleStatus = .stopped
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var intentionalStop = false
    private let lock = NSLock()
    private let stateActor = ProcessStateActor()

    var onLog: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

    var detectedBinaryPath: String? {
        try? resolveMihomoBinary()
    }

    var isRunning: Bool {
        lock.withLock {
            process?.isRunning == true
        }
    }

    deinit {
        stop()
    }

    @discardableResult
    func start(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        if let runningPid = lock.withLock({ process?.isRunning == true ? process?.processIdentifier : nil }) {
            return .running(pid: runningPid)
        }

        lock.withLock {
            intentionalStop = false
            status = .starting
        }
        Task {
            await stateActor.setIntentionalStop(false)
            await stateActor.setStatus(.starting)
        }

        let binary = try resolveMihomoBinary()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)

        let configFileURL = URL(fileURLWithPath: configPath).standardizedFileURL.resolvingSymlinksInPath()
        let configDirectoryURL = configFileURL.deletingLastPathComponent()
        let workingDirectoryURL: URL
        if configDirectoryURL.lastPathComponent == "config" {
            workingDirectoryURL = configDirectoryURL.deletingLastPathComponent()
        } else {
            workingDirectoryURL = configDirectoryURL
        }
        proc.currentDirectoryURL = workingDirectoryURL

        // `-d` pins mihomo runtime home directory to ClashBar working root.
        // This prevents fallback to ~/.config/mihomo for provider/cache updates.
        let args = ["-d", workingDirectoryURL.path, "-f", configPath, "-ext-ctl", controller]
        proc.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading

        wireLogPipe(stdout.fileHandleForReading)
        wireLogPipe(stderr.fileHandleForReading)

        proc.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            let code = terminatedProcess.terminationStatus
            self.handleProcessTermination(terminatedProcess, code: code)
        }

        do {
            try proc.run()
            lock.withLock {
                process = proc
                status = .running(pid: proc.processIdentifier)
            }
            Task {
                await stateActor.setStatus(.running(pid: proc.processIdentifier))
            }
            onLog?("[mihomo started] pid=\(proc.processIdentifier) controller=\(controller) binary=\(binary) workdir=\(workingDirectoryURL.path)")
            return status
        } catch {
            let reason = "Failed to launch mihomo: \(error.localizedDescription)"
            lock.withLock {
                status = .failed(reason: reason)
                intentionalStop = false
                releasePipeHandlesLocked()
            }
            Task {
                await stateActor.setIntentionalStop(false)
                await stateActor.setStatus(.failed(reason: reason))
            }
            onLog?("[mihomo error] \(reason)")
            throw error
        }
    }

    func stop() {
        let running: Process? = lock.withLock {
            intentionalStop = true
            return process
        }
        Task {
            await stateActor.setIntentionalStop(true)
        }

        guard let running else {
            lock.withLock {
                status = .stopped
                intentionalStop = false
                releasePipeHandlesLocked()
            }
            Task {
                await stateActor.setIntentionalStop(false)
                await stateActor.setStatus(.stopped)
            }
            return
        }

        guard running.isRunning else {
            handleProcessTermination(running, code: running.terminationStatus)
            return
        }

        onLog?("[mihomo stop] terminate signal sent pid=\(running.processIdentifier)")
        running.terminate()

        if waitForProcessExit(running, timeout: 2.0) {
            handleProcessTermination(running, code: running.terminationStatus)
            return
        }

        onLog?("[mihomo stop] force kill pid=\(running.processIdentifier)")
        _ = Darwin.kill(running.processIdentifier, SIGKILL)
        _ = waitForProcessExit(running, timeout: 1.0)
        handleProcessTermination(running, code: running.terminationStatus)
    }

    @discardableResult
    func restart(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        stop()
        return try start(configPath: configPath, controller: controller)
    }

    private func handleProcessTermination(_ terminatedProcess: Process, code: Int32) {
        let outcome = lock.withLock { () -> (handled: Bool, intentional: Bool) in
            guard let current = process, current === terminatedProcess else {
                return (false, false)
            }

            let intentional = intentionalStop
            intentionalStop = false
            process = nil
            status = .stopped
            releasePipeHandlesLocked()
            return (true, intentional)
        }

        guard outcome.handled else { return }
        Task {
            await stateActor.setIntentionalStop(false)
            await stateActor.setStatus(.stopped)
        }

        if outcome.intentional {
            onLog?("[mihomo stopped] exit=\(code)")
        } else {
            onLog?("[mihomo terminated] exit=\(code)")
            onTermination?(code)
        }
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        return !process.isRunning
    }

    private func resolveMihomoBinary() throws -> String {
        let fm = FileManager.default
        let resourceRoots = AppResourceBundleLocator.candidateResourceRoots()
        for root in resourceRoots {
            let candidates = [
                root.appendingPathComponent("bin/mihomo").path,
                root.appendingPathComponent("Resources/bin/mihomo").path,
                root.appendingPathComponent("mihomo").path
            ]
            for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
                try validateBinarySecurity(at: candidate)
                return candidate
            }
        }

        throw NSError(
            domain: "ClashBar.Core",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "mihomo binary not found in app resources"]
        )
    }

    private func validateBinarySecurity(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])

        if values.isSymbolicLink == true {
            throw NSError(
                domain: "ClashBar.Core",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary path must not be a symbolic link: \(path)"]
            )
        }
        if values.isRegularFile != true {
            throw NSError(
                domain: "ClashBar.Core",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary must be a regular file: \(path)"]
            )
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let uid = Int(getuid())
        if let owner = attrs[.ownerAccountID] as? NSNumber {
            let ownerID = owner.intValue
            if ownerID != 0 && ownerID != uid {
                throw NSError(
                    domain: "ClashBar.Core",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "mihomo binary owner must be current user or root: \(path)"]
                )
            }
        }

        if let perm = attrs[.posixPermissions] as? NSNumber {
            let mode = perm.intValue
            // Refuse group-writable or world-writable executables.
            if (mode & 0o022) != 0 {
                throw NSError(
                    domain: "ClashBar.Core",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "mihomo binary permissions are too permissive (writable by group/others): \(path)"]
                )
            }
        }

    }

    private func wireLogPipe(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            let data = readable.availableData
            if data.isEmpty { return }
            guard let line = String(data: data, encoding: .utf8) else { return }
            self?.onLog?(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func releasePipeHandlesLocked() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle?.closeFile()
        stderrHandle?.closeFile()
        stdoutHandle = nil
        stderrHandle = nil
    }
}
