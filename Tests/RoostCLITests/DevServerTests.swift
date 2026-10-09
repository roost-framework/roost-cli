import Foundation
import Testing
@testable import RoostCLI

@Suite("Dev server")
struct DevServerTests {
    @Test("roost server skips a port that is already listening")
    func portFallback() throws {
        let fd = socket(AF_INET, streamSocket, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        // Port 0 lets the system pick one; getsockname reports which.
        let listening = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        try #require(listening)

        let busy = Int(UInt16(bigEndian: address.sin_port))
        #expect(Build.freePort(from: busy) != busy)
    }

    @Test("Each app keeps the same Postgres port across runs")
    func stablePostgresPort() {
        #expect(DevDatabase.hostPort("TodoApp") == DevDatabase.hostPort("todoapp"))
        #expect((15432..<16432).contains(DevDatabase.hostPort("TodoApp")))
    }
}
