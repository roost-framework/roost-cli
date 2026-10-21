import ArgumentParser

@main
struct RoostCLI: AsyncParsableCommand {
    static let version = "3.0.0"
    /// Minimum swift-roost release that generated apps depend on.
    static let frameworkVersion = "2.4.0"

    static let configuration = CommandConfiguration(
        commandName: "roost",
        abstract: "The Roost web framework CLI",
        version: version,
        subcommands: [
            New.self,
            Gen.self,
            Migrate.self,
            DB.self,
            Routes.self,
            Server.self,
            Build.self,
        ]
    )
}
