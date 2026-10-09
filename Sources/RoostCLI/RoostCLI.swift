import ArgumentParser

@main
struct RoostCLI: AsyncParsableCommand {
    static let version = "2.1.1"
    /// Minimum swift-roost release that generated apps depend on.
    static let frameworkVersion = "2.1.3"

    static let configuration = CommandConfiguration(
        commandName: "roost",
        abstract: "The Roost web framework CLI",
        version: version,
        subcommands: [
            New.self,
            Gen.self,
            Migrate.self,
            Server.self,
            Build.self,
            Spectro.self,
        ]
    )
}
