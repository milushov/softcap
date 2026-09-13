import Testing
import Foundation

/// The gate on the machine-name check, tested apart from the suite it sits in.
///
/// Apart on purpose: `NoPersonalDataInTheRepository` holds exactly the checks
/// that scan the repository, the README counts them, and a test of the gate is
/// not one of them — it examines the checker, not the tree.
@Suite struct TheMachineNameCheckKnowsWhereItIs {

    /// On CI the check stands down. The runner's user is literally named
    /// `runner` — ordinary prose in any file that describes the workflow — and
    /// the author's machine is never the one CI provides, so there is nothing
    /// true for it to find there.
    @Test func standsDownOnCI() {
        let names = NoPersonalDataInTheRepository
            .namesOfThisMachine(environment: ["CI": "true"])
        #expect(names.isEmpty)
    }

    /// Everywhere else it answers with the names this machine actually has.
    @Test func knowsItsMachineEverywhereElse() {
        let names = NoPersonalDataInTheRepository.namesOfThisMachine(environment: [:])
        let user = NSUserName().lowercased()
        if user.count > 3 {
            #expect(names.contains(user))
        }
    }
}
