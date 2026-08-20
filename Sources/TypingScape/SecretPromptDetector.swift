import Foundation

/// Decides whether a just-submitted shell command is one that will ask for
/// a secret on the next line — pure/testable so the "does this pause
/// tracking" rule can be verified without a live event tap.
///
/// This exists because `TerminalKeyTracker` taps raw keystrokes and has no
/// way to tell a password prompt from any other line: a terminal is one
/// undifferentiated text grid, with nothing like the `AXSecureTextField`
/// subrole that `FocusedTextTracker` can check in a GUI app. Watching what
/// the user *ran* is the only signal available before the secret is typed.
///
/// ponytail: heuristic by nature — an unlisted command that prompts for a
/// password (a company-internal wrapper, an unusual VPN client) still gets
/// through to the spell-check filter alone. Covers the common cases rather
/// than claiming completeness.
enum SecretPromptDetector {
    /// Commands whose *own* prompt asks for a password/passphrase.
    private static let secretPromptingCommands: Set<String> = [
        "sudo", "su", "doas",
        "ssh", "scp", "sftp", "ssh-add", "ssh-keygen", "ssh-copy-id",
        "passwd", "gpg", "openssl",
        "mysql", "psql", "mongosh", "redis-cli",
        "security", "kinit", "vault", "op",
    ]

    /// True if `line` (one submitted command line) is likely to be followed
    /// by a secret typed at a prompt.
    static func promptsForSecret(_ line: String) -> Bool {
        // A pipeline/chain prompts for a secret if *any* of its stages does
        // ("echo x | sudo tee y", "cd /tmp && ssh host") — checking only the
        // first word would miss every one of those.
        let separators = CharacterSet(charactersIn: "|;&")
        for segment in line.components(separatedBy: separators) {
            guard let command = firstCommandWord(of: segment) else { continue }
            if secretPromptingCommands.contains(command) { return true }
        }
        return false
    }

    /// The actual command in a segment, skipping leading `VAR=value`
    /// assignments and reducing a path (`/usr/bin/sudo`) to its last
    /// component.
    private static func firstCommandWord(of segment: String) -> String? {
        for token in segment.split(separator: " ", omittingEmptySubsequences: true) {
            let word = String(token)
            // `FOO=bar cmd` — the assignment isn't the command.
            if word.contains("="), !word.hasPrefix("=") { continue }
            return String(word.split(separator: "/").last ?? Substring(word))
        }
        return nil
    }
}
