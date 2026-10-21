import ArgumentParser

struct Routes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "routes",
        abstract: "List the app's routes in matching order, like mix phx.routes"
    )

    func run() async throws { try runApp(["routes"], database: false, minimumFramework: "2.4.0") }
}
