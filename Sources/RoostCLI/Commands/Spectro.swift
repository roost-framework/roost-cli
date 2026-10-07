import ArgumentParser
import Foundation

struct Spectro: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spectro",
        abstract: "Run the app's Spectro CLI",
        discussion: """
            Passes every argument to the spectro executable from this app's dependencies, \
            so its version always matches the Spectro library in Package.resolved.

              roost spectro database create
              roost spectro migrate status
              roost spectro --help
            """
    )

    @Argument(parsing: .captureForPassthrough, help: "Arguments for spectro.")
    var arguments: [String] = []

    func run() async throws {
        let context = try resolveProject()
        FileManager.default.changeCurrentDirectoryPath(context.root)
        // exec keeps stdin, signals, and spectro's exit status intact.
        let argv = (["swift", "run", "spectro"] + arguments).map { strdup($0) } + [nil]
        execvp("swift", argv)
        RoostUI.noora.error(.alert("Could not run swift: \(String(cString: strerror(errno)))"))
        throw ExitCode.failure
    }
}
