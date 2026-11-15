import Foundation
import Testing

@Suite("EPUBCheck lookup")
struct EPUBCheckLookupTests {
    private func resolve(
        environment: [String: String] = [:],
        installed: Set<String> = []
    ) -> EPUBCheck.Resolution {
        EPUBCheck.resolve(environment: environment, isExecutable: { installed.contains($0) })
    }

    @Test("finds the Homebrew launcher")
    func foundInHomebrew() {
        #expect(resolve(installed: ["/opt/homebrew/bin/epubcheck"]) == .found("/opt/homebrew/bin/epubcheck"))
    }

    @Test("finds a launcher on PATH, as on a CI runner")
    func foundOnPath() {
        let environment = ["PATH": "/usr/bin:/somewhere/bin"]
        #expect(resolve(environment: environment, installed: ["/somewhere/bin/epubcheck"])
            == .found("/somewhere/bin/epubcheck"))
    }

    @Test("EPUBCHECK_PATH wins over the default locations")
    func explicitPath() {
        let environment = ["EPUBCHECK_PATH": "/custom/epubcheck"]
        let installed: Set = ["/custom/epubcheck", "/opt/homebrew/bin/epubcheck"]
        #expect(resolve(environment: environment, installed: installed) == .found("/custom/epubcheck"))
    }

    @Test("a missing epubcheck skips with a loud reason by default")
    func missingSkips() {
        guard case let .skip(reason) = resolve() else {
            Issue.record("expected a skip")
            return
        }
        #expect(reason.contains("NOT VALIDATED"))
        #expect(reason.contains("REQUIRE_EPUBCHECK"))
    }

    @Test("a missing epubcheck fails when REQUIRE_EPUBCHECK is set")
    func missingFailsWhenRequired() {
        guard case let .fail(reason) = resolve(environment: ["REQUIRE_EPUBCHECK": "1"]) else {
            Issue.record("expected a failure")
            return
        }
        #expect(reason.contains("REQUIRE_EPUBCHECK"))
    }

    @Test("an empty or zero REQUIRE_EPUBCHECK does not require it")
    func notRequired() {
        for value in ["", "0", "false"] {
            guard case .skip = resolve(environment: ["REQUIRE_EPUBCHECK": value]) else {
                Issue.record("value \(value) must not require epubcheck")
                return
            }
        }
    }

    @Test("an installed epubcheck is used even when required")
    func foundWhenRequired() {
        let environment = ["REQUIRE_EPUBCHECK": "1"]
        #expect(resolve(environment: environment, installed: ["/usr/local/bin/epubcheck"])
            == .found("/usr/local/bin/epubcheck"))
    }
}
