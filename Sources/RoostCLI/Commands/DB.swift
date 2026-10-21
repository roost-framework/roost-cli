import ArgumentParser

struct DB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "db",
        abstract: "Create, drop, set up, and seed the app's database",
        discussion: """
            Runs with the app's own database configuration, like mix ecto.create and friends:

              create  Create the database unless it exists
              drop    Drop the database, closing its connections
              seed    Run Seeds/<env>.sql
              setup   create, migrate up, then seed when Seeds/<env>.sql exists
              reset   drop, then setup

            ROOST_ENV picks the database: ROOST_ENV=test roost db setup prepares the test database.
            drop and reset refuse ROOST_ENV=prod.
            """
    )

    enum Action: String, CaseIterable, ExpressibleByArgument {
        case create, drop, seed, setup, reset
    }

    @Argument(help: "create, drop, seed, setup, or reset")
    var action: Action

    func run() async throws { try runApp(["db", action.rawValue], minimumFramework: "2.4.0") }
}
