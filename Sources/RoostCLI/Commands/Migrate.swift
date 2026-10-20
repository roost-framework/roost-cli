import ArgumentParser
import Foundation

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Run database migrations",
        subcommands: [
            MigrateUp.self,
            MigrateDown.self,
            MigrateStatus.self,
        ],
        defaultSubcommand: MigrateUp.self
    )
}

struct MigrateUp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "up", abstract: "Run pending migrations with the app's configuration")
    func run() async throws { try runApp(["migrate", "up"]) }
}

struct MigrateDown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "down", abstract: "Rollback the last migration")
    func run() async throws { try runApp(["migrate", "down"]) }
}

struct MigrateStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show migration status")
    func run() async throws { try runApp(["migrate", "status"]) }
}
