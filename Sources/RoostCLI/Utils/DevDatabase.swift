import ArgumentParser
import Foundation
@preconcurrency import Noora

/// The app's development Postgres, in a container of its own, so `roost server`,
/// `roost migrate`, and `roost spectro` never reach a Postgres installed on the host.
enum DevDatabase {
    /// Matches the Postgres that CI tests against.
    static let image = "postgres:18"

    /// Starts the app's Postgres container and points `DB_HOST`, `DB_PORT`, `DB_USER`,
    /// and `DB_PASSWORD` at it for this process and its children.
    ///
    /// Apps without migrations get no container. An explicit `DB_HOST` means the
    /// developer runs their own database, so it is left alone.
    static func start(root: String, appName: String) throws {
        guard FileManager.default.fileExists(atPath: ProjectDiscovery.migrationsDir(root: root)) else { return }
        let environment = ProcessInfo.processInfo.environment
        if let host = environment["DB_HOST"] {
            print("[roost] DB_HOST is set; using the Postgres at \(host).")
            return
        }
        guard let runtime = environment["ROOST_CONTAINER_RUNTIME"] ?? installedRuntime() else {
            print("[roost] Install Apple's container or Docker to run Postgres in a container. Using localhost:5432.")
            return
        }

        let name = containerName(appName)
        let port = hostPort(appName)
        if !postgresAnswers(on: port) {
            print("[roost] Starting Postgres in \(name) (\(runtime))...")
            // The image download on first run can take a while.
            let started = try call(runtime, "start", name)
                || call(runtime, "run", "-d", "--name", name, "-p", "127.0.0.1:\(port):5432",
                        "-e", "POSTGRES_PASSWORD=postgres", image, quiet: false, timeout: 600)
            guard started else {
                RoostUI.noora.error(.alert(
                    "Could not start Postgres with \(.command(runtime)).",
                    takeaways: [
                        "Apple's container: run \(.command("container system start")), and update it if it rejects -p.",
                        "Docker: start Docker Desktop.",
                        "Or set DB_HOST to use a Postgres you run yourself.",
                    ]
                ))
                throw ExitCode.failure
            }
            let deadline = Date().addingTimeInterval(30)
            while !postgresAnswers(on: port) {
                guard Date() < deadline else {
                    RoostUI.noora.error(.alert(
                        "Postgres in \(name) did not answer on 127.0.0.1:\(port) within 30s.",
                        takeaways: [
                            "See its log: \(.command("\(runtime) logs \(name)"))",
                            "Apple's container: macOS blocks published ports until you allow container-runtime-linux in System Settings > Privacy & Security > Local Network.",
                        ]
                    ))
                    throw ExitCode.failure
                }
                usleep(500_000)
            }
        }

        setenv("DB_HOST", "127.0.0.1", 1)
        setenv("DB_PORT", String(port), 1)
        setenv("DB_USER", "postgres", 1)
        setenv("DB_PASSWORD", "postgres", 1)
        print("[roost] Postgres: 127.0.0.1:\(port) (\(name), \(runtime))")
    }

    static func containerName(_ appName: String) -> String {
        "roost-\(appName.lowercased())-db"
    }

    /// A port derived from the app name, so `DB_PORT` stays the same across runs.
    static func hostPort(_ appName: String) -> Int {
        // ponytail: two apps can hash to the same port, and the second container then fails
        // to publish it. Store a chosen port per app if that happens in practice.
        let hash = appName.lowercased().utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return 15432 + Int(hash % 1000)
    }

    /// Whether Postgres answers on 127.0.0.1:`port`, where the app connects. Accepting the
    /// connection is not enough: a runtime's port forwarder accepts connections it cannot pass on.
    static func postgresAnswers(on port: Int) -> Bool {
        guard let fd = Platform.connectLoopback(port) else { return false }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // SSLRequest, which Postgres answers with a single byte, S or N.
        let sslRequest: [UInt8] = [0, 0, 0, 8, 0x04, 0xD2, 0x16, 0x2F]
        #if os(Linux)
        let sent = send(fd, sslRequest, sslRequest.count, Int32(MSG_NOSIGNAL))
        #else
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let sent = send(fd, sslRequest, sslRequest.count, 0)
        #endif
        var reply: UInt8 = 0
        return sent == sslRequest.count && recv(fd, &reply, 1, 0) == 1
            && (reply == UInt8(ascii: "S") || reply == UInt8(ascii: "N"))
    }

    /// Apple's container first, then Docker.
    private static func installedRuntime() -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return ["container", "docker"].first { tool in
            path.split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(tool)") }
        }
    }

    /// Runs a runtime command and returns whether it exited 0. A stopped Docker Desktop can
    /// leave the `docker` client waiting forever, so a command that outlives `timeout` fails.
    private static func call(_ arguments: String..., quiet: Bool = true, timeout: TimeInterval = 30) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        if quiet { process.standardError = FileHandle.nullDevice }
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            guard Date() < deadline else {
                kill(process.processIdentifier, SIGKILL)
                RoostUI.noora.error(.alert(
                    "\(.command(arguments[0])) did not respond within \(Int(timeout))s.",
                    takeaways: ["Check that \(arguments[0] == "docker" ? "Docker Desktop" : "its service") is running."]
                ))
                throw ExitCode.failure
            }
            usleep(50_000)
        }
        return process.terminationStatus == 0
    }
}
