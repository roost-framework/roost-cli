import ArgumentParser
import Foundation

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Run database migrations with the app's configuration",
        discussion: """
            Passes every argument to the app's migrate command, so migrations use the server's database.

              roost migrate                  apply pending migrations
              roost migrate status
              roost migrate down             roll back the newest migration
              roost migrate down --step 2
              roost migrate down --all
            """
    )

    @Argument(parsing: .captureForPassthrough, help: "up (the default), down, or status, and their options.")
    var arguments: [String] = []

    func run() async throws {
        // Help needs no database.
        let help = arguments.contains { ["help", "--help", "-h", "-help"].contains($0) }
        try runApp(["migrate"] + (arguments.isEmpty ? ["up"] : arguments), database: !help)
    }
}
