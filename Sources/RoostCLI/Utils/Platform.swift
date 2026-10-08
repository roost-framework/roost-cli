import Foundation

enum Platform {
    /// The pinned Tailwind CSS release. Unpinned downloads broke new projects at v4.
    static let tailwindVersion = "v4.3.3"

    /// Returns the Tailwind CSS binary name for the current OS and architecture.
    static var tailwindBinaryName: String {
        #if os(macOS)
            #if arch(arm64)
                return "tailwindcss-macos-arm64"
            #else
                return "tailwindcss-macos-x64"
            #endif
        #else
            #if arch(arm64)
                return "tailwindcss-linux-arm64"
            #else
                return "tailwindcss-linux-x64"
            #endif
        #endif
    }
}
