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
        let ready = { try call(runtime, "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-q") }

        if try !ready() {
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
            let deadline = Date().addingTimeInterval(60)
            while try !ready() {
                guard Date() < deadline else {
                    RoostUI.noora.error(.alert(
                        "Postgres in \(name) did not accept connections within 60s.",
                        takeaways: ["See why: \(.command("\(runtime) logs \(name)"))"]
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
