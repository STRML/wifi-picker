import Testing
@testable import WifiPickerCore

@Suite struct JoinPolicyTests {
    @Test func securedUnknownNetworkAsksForAPasswordBeforeJoining() {
        #expect(JoinPolicy.needsPasswordUpFront(secure: true, known: false))
    }

    @Test func knownOrOpenNetworksJoinWithoutAsking() {
        #expect(JoinPolicy.needsPasswordUpFront(secure: true, known: true) == false)
        #expect(JoinPolicy.needsPasswordUpFront(secure: false, known: false) == false)
    }

    @Test func aSavedNetworkWithoutAKeychainPasswordOpensTheSheet() {
        let outcome = JoinPolicy.outcome(forErrorCode: -3906, message: "boom", hadPassword: false, secure: true)
        #expect(outcome == .needsPassword)
    }

    @Test func anOpenNetworkThatFailsToJoinIsAPlainFailure() {
        let outcome = JoinPolicy.outcome(forErrorCode: -3905, message: "timed out", hadPassword: false, secure: false)
        #expect(outcome == .failed("timed out"))
    }

    @Test func authenticationFailuresWithAPasswordMeanWrongPassword() {
        for code in [-3905, -3906, -3909, -3912, -3924, -3925] {
            let outcome = JoinPolicy.outcome(forErrorCode: code, message: "x", hadPassword: true, secure: true)
            #expect(outcome == .wrongPassword, "code \(code)")
        }
    }

    @Test func otherFailuresWithAPasswordKeepTheirMessage() {
        let outcome = JoinPolicy.outcome(forErrorCode: -3929, message: "ipc", hadPassword: true, secure: true)
        #expect(outcome == .failed("ipc"))
    }
}
