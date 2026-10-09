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
