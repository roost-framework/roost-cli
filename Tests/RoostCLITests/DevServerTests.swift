import Foundation
import Testing
@testable import RoostCLI

@Suite("Dev server")
struct DevServerTests {
    /// Listens on a port the system picks and never accepts, which the kernel still
    /// completes connections for. Close the returned socket.
    private func listener() throws -> (fd: Int32, port: Int) {
        let fd = socket(AF_INET, streamSocket, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let listening = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        try #require(listening)
        return (fd, Int(UInt16(bigEndian: address.sin_port)))
    }

    @Test("roost server skips a port that is already listening")
    func portFallback() throws {
        let (fd, busy) = try listener()
        defer { close(fd) }
        #expect(Build.freePort(from: busy) != busy)
    }

    @Test("A port that accepts connections without speaking Postgres is not ready")
    func postgresProbe() throws {
        let (fd, port) = try listener()
        defer { close(fd) }
        #expect(!DevDatabase.postgresAnswers(on: port))
    }

    @Test("Each app keeps the same Postgres port across runs")
    func stablePostgresPort() {
        #expect(DevDatabase.hostPort("TodoApp") == DevDatabase.hostPort("todoapp"))
        #expect((15432..<16432).contains(DevDatabase.hostPort("TodoApp")))
    }
}

@Suite("App commands")
struct AppCommandTests {
    @Test("Commands added in a newer framework stop apps that resolved an older one")
    func frameworkVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ProjectDiscovery.resolvedFrameworkVersion(root: root.path) == nil)
        try """
            {"pins": [
              {"identity": "nexus", "kind": "remoteSourceControl", "state": {"revision": "a", "version": "9.0.0"}},
              {"identity": "swift-roost", "kind": "remoteSourceControl", "state": {"revision": "b", "version": "2.3.0"}}
            ], "version": 3}
            """.write(to: root.appendingPathComponent("Package.resolved"), atomically: true, encoding: .utf8)
        #expect(ProjectDiscovery.resolvedFrameworkVersion(root: root.path) == "2.3.0")
        #expect(isVersion("2.3.0", olderThan: "2.4.0"))
        #expect(isVersion("2.3.10", olderThan: "2.4.0"))
        #expect(!isVersion("2.4.0", olderThan: "2.4.0"))
        #expect(!isVersion("2.10.0", olderThan: "2.4.0"))
        #expect(!isVersion("3.0", olderThan: "2.4.0"))
    }
}
