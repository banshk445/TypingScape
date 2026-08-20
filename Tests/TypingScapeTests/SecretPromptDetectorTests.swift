import XCTest
@testable import TypingScape

final class SecretPromptDetectorTests: XCTestCase {
    func testPlainSecretPromptingCommands() {
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("sudo rm -rf /tmp/x"))
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("ssh user@host"))
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("passwd"))
    }

    func testOrdinaryCommandsAreNotPaused() {
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("git status"))
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("npm run build"))
        XCTAssertFalse(SecretPromptDetector.promptsForSecret(""))
    }

    func testLeadingWhitespaceAndEnvAssignments() {
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("   sudo apt update"))
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("FOO=bar sudo make install"))
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("FOO=bar git push"))
    }

    func testAbsolutePathInvocation() {
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("/usr/bin/sudo whoami"))
    }

    func testAnyStageOfAPipelineOrChainCounts() {
        // Checking only the first word would miss every one of these.
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("echo hi | sudo tee /etc/x"))
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("cd /tmp && ssh host"))
        XCTAssertTrue(SecretPromptDetector.promptsForSecret("make; sudo make install"))
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("cat a | grep b | wc -l"))
    }

    func testSubstringsOfOtherWordsDontFalselyMatch() {
        // "pseudo"/"sudoku" contain "sudo" but aren't it.
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("pseudo-terminal --test"))
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("sudoku solve"))
        // ...and a real command whose *argument* merely mentions one.
        XCTAssertFalse(SecretPromptDetector.promptsForSecret("git commit -m \"use sudo here\""))
    }
}
