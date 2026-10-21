import ArgumentParser

struct GenLive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "live",
        abstract: "Generate a resource whose index is a live page (like mix phx.gen.live)",
        discussion: """
            Writes everything 'roost gen resource' does for HTML, except that the index is a
            LivePage: the list, a create form validated as you type, and delete, without
            page reloads. Show, new, and edit stay ordinary pages, and the live forms post
            to the controller when JavaScript is unavailable.
            """
    )

    @Argument(help: "Model name in PascalCase (e.g. Post)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. title:string body:text published:bool)")
    var fields: [String] = []

    @Option(name: .long, help: "Scope foreign key column (e.g. user_id)")
    var scope: String?

    func run() async throws {
        // Parsed, not built with GenResource(): unparsed flags can't be read.
        var resource = try GenResource.parse([name] + fields + (scope.map { ["--scope", $0] } ?? []))
        resource.live = true
        try await resource.run()
    }
}
