import Foundation
import Testing
import WifiPickerCore

@MainActor
@Suite struct PickerModelTests {
    // MARK: - Panel open / close / cancel lifecycle

    @Test func openFreezesCacheEntersLiveModeAndScansWhenCold() async {
        let clock = TestClock()
        let env = FakeEnvironment(cachedSamples: [sample("Cafe"), sample("Home", known: true)])
        let model = PickerModel(environment: env, clock: clock.makeClock())
        var events: [PanelLifecycleEvent] = []
        model.onPanelEvent = { events.append($0) }

        let opened = await model.open().value
        #expect(opened)
        #expect(model.panelPhase == .open)
        #expect(env.locationRequests == 1)
        #expect(env.liveChanges == [true])
        #expect(env.scanCount == 1)
        #expect(events == [.opened])
        #expect(model.columns[ColumnKind.known.rawValue].slots == ["Home"])
        #expect(model.columns[ColumnKind.other.rawValue].slots == ["Cafe"])

        // Opening again while already open is a no-op.
        #expect(await model.open().value == false)
        #expect(env.scanCount == 1)

        model.close()
        #expect(model.panelPhase == .closed)
        #expect(env.liveChanges == [true, false])
        #expect(events == [.opened, .closed])
    }

    @Test func closeWhileOpeningCancelsWithoutOpeningOrEnteringLiveMode() async {
        let env = FakeEnvironment(cachedSamples: [sample("Cafe")])
        env.suspendCacheRead = true
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        var events: [PanelLifecycleEvent] = []
        model.onPanelEvent = { events.append($0) }

        let task = model.open()
        await drainMainActor()
        #expect(model.panelPhase == .opening)
        #expect(env.pendingCacheReadCount == 1)

        model.close()
        #expect(model.panelPhase == .closed)

        env.resumeNextCacheRead()
        #expect(await task.value == false)
        #expect(model.panelPhase == .closed)
        #expect(env.liveChanges == [false])
        #expect(env.scanCount == 0)
        #expect(events == [.closed])
    }

    @Test func rapidOpenCloseOpenDoesNotLetFirstOpenClobberSecond() async {
        let env = FakeEnvironment()
        env.suspendCacheRead = true
        let model = PickerModel(environment: env, clock: TestClock().makeClock())

        let first = model.open()
        await drainMainActor()
        model.close()
        let second = model.open()
        await drainMainActor()
        #expect(env.pendingCacheReadCount == 2)

        env.resumeNextCacheRead(with: [sample("Stale")])
        #expect(await first.value == false)
        #expect(model.panelPhase == .opening)

        env.resumeNextCacheRead(with: [sample("Fresh")])
        #expect(await second.value == true)
        #expect(model.panelPhase == .open)
        #expect(model.columns[ColumnKind.other.rawValue].slots == ["Fresh"])
    }

    // MARK: - Cache freshness (replaces ScanPolicyTests through the real coordinator interface)

    @Test func skipsScanOnOpenWhenCacheUpdatedWithinFreshnessWindow() async {
        let clock = TestClock()
        let env = FakeEnvironment(cachedSamples: [sample("Home", known: true)])
        let model = PickerModel(environment: env, clock: clock.makeClock())

        env.send(.cacheUpdated)
        await drainMainActor()

        // 120 seconds later: still fresh.
        clock.advance(by: PickerModel.cacheFreshness)
        #expect(await model.open().value)
        #expect(env.scanCount == 0)

        // Clock moving backwards counts as fresh.
        model.close()
        clock.set(t0.addingTimeInterval(-500))
        #expect(await model.open().value)
        #expect(env.scanCount == 0)

        // 121 seconds after last cache update: stale, triggers scan.
        model.close()
        clock.set(t0.addingTimeInterval(PickerModel.cacheFreshness + 1))
        #expect(await model.open().value)
        #expect(env.scanCount == 1)
    }

    // MARK: - Join flow, password sheet, Rescan gating, and localized CoreWLAN errors

    @Test func unknownSecuredNetworkPromptsUpFrontAndHandlesWrongPasswordAndSuccess() async {
        let env = FakeEnvironment(cachedSamples: [sample("Coffee", secure: true, known: false)])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.activate("Coffee")
        #expect(env.joins.isEmpty)
        #expect(model.passwordRequest == PasswordRequest(ssid: "Coffee", error: nil))
        #expect(model.joinState == .promptingPassword(ssid: "Coffee", error: nil))

        // Arrows and confirm yield to the password field while sheet is visible.
        #expect(model.handleKey(.arrow(.down)) == false)
        #expect(model.handleKey(.confirm) == false)

        model.submitPassword("wrong")
        #expect(env.joins == [.init(ssid: "Coffee", password: "wrong", secure: true)])
        #expect(model.joiningSSID == "Coffee")
        #expect(model.canRescan == false)
        #expect(model.passwordRequest == PasswordRequest(ssid: "Coffee", error: nil))
        #expect(model.statusLine == "Joining Coffee…")
        #expect(model.statusIsError == false)

        // Wrong password returns to password sheet with error.
        let wrong = JoinPolicy.outcome(forErrorCode: -3924, hadPassword: true, secure: true)
        #expect(wrong == .wrongPassword)
        env.send(.joinFinished(ssid: "Coffee", outcome: wrong))
        await drainMainActor()
        #expect(model.joinState == .promptingPassword(ssid: "Coffee", error: "Wrong password"))
        #expect(model.passwordRequest == PasswordRequest(ssid: "Coffee", error: "Wrong password"))

        // Correct password succeeds and clears sheet.
        model.submitPassword("right")
        env.send(.joinFinished(ssid: "Coffee", outcome: .connected))
        await drainMainActor()
        #expect(model.joinState == .idle)
        #expect(model.passwordRequest == nil)
    }

    @Test func savedNetworkWithoutKeychainPasswordFallsBackToPasswordSheet() async {
        let env = FakeEnvironment(cachedSamples: [sample("Office", secure: true, known: true)])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.activate("Office")
        #expect(env.joins == [.init(ssid: "Office", password: nil, secure: true)])

        let outcome = JoinPolicy.outcome(forErrorCode: -3906, hadPassword: false, secure: true)
        #expect(outcome == .needsPassword)
        env.send(.joinFinished(ssid: "Office", outcome: outcome))
        await drainMainActor()
        #expect(model.passwordRequest == PasswordRequest(ssid: "Office", error: nil))
    }

    @Test func joinFailuresSurfaceLocalizedCoreWLANErrorsInStatusLine() async {
        let env = FakeEnvironment(cachedSamples: [sample("OpenCafe", secure: false, known: false)])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.activate("OpenCafe")
        #expect(env.joins == [.init(ssid: "OpenCafe", password: nil, secure: false)])

        let apFull = JoinPolicy.outcome(
            forErrorCode: -3913,
            fallbackMessage: "The operation couldn’t be completed. (com.apple.wifi.apple80211API.error error -3913.)",
            hadPassword: false,
            secure: false
        )
        #expect(apFull == .failed("Access point is full"))
        env.send(.joinFinished(ssid: "OpenCafe", outcome: apFull))
        await drainMainActor()
        #expect(model.statusLine == "Access point is full")
        #expect(model.statusIsError)

        // Unknown error code with generic Foundation boilerplate falls back cleanly.
        let generic = JoinPolicy.outcome(
            forErrorCode: -9999,
            fallbackMessage: "The operation couldn’t be completed. (com.apple.wifi error -9999.)",
            hadPassword: true,
            secure: true
        )
        #expect(generic == .failed("Couldn’t join network"))

        // Unknown error code with a descriptive non-generic message preserves it.
        let custom = JoinPolicy.outcome(
            forErrorCode: -9999,
            fallbackMessage: "Network not in range",
            hadPassword: false,
            secure: false
        )
        #expect(custom == .failed("Network not in range"))
    }

    @Test func allCoreWLANAuthCodesWithPasswordMeanWrongPassword() {
        for code in [-3905, -3906, -3909, -3912, -3924, -3925] {
            let outcome = JoinPolicy.outcome(forErrorCode: code, hadPassword: true, secure: true)
            #expect(outcome == .wrongPassword, "code \(code)")
        }
    }

    // MARK: - Escape & reopening during an in-flight join

    @Test func escapeDismissesIdlePasswordSheetWithoutClosingPanel() async {
        let env = FakeEnvironment(cachedSamples: [sample("Locked", secure: true, known: false)])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.activate("Locked")
        #expect(model.passwordRequest != nil)

        #expect(model.handleKey(.escape))
        #expect(model.passwordRequest == nil)
        #expect(model.panelPhase == .open)

        // Pressing Esc again closes the panel.
        #expect(model.handleKey(.escape))
        #expect(model.panelPhase == .closed)
    }

    @Test func escapeDuringInFlightJoinClosesPanelWithoutStoppingJoin() async {
        let env = FakeEnvironment(cachedSamples: [
            sample("Locked", secure: true, known: false),
            sample("Other", secure: false, known: false),
        ])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.activate("Locked")
        model.submitPassword("secret")
        #expect(model.joiningSSID == "Locked")

        // Esc closes the panel while join keeps running.
        #expect(model.handleKey(.escape))
        #expect(model.panelPhase == .closed)
        #expect(model.joiningSSID == "Locked")
        #expect(model.passwordRequest == nil)

        // Reopening while still joining preserves the active join indicator and blocks another join.
        #expect(await model.open().value)
        #expect(model.joiningSSID == "Locked")
        #expect(model.passwordRequest == nil)
        model.activate("Other")
        #expect(env.joins.count == 1)

        // Closing again and finishing while closed cleanly resets join state.
        model.close()
        env.send(.joinFinished(ssid: "Locked", outcome: .connected))
        await drainMainActor()
        #expect(model.joinState == .idle)
    }

    // MARK: - Power toggle race, location gating, dimming clock

    @Test func optimisticPowerToggleIgnoresStaleInterfaceEventsUntilSettled() async {
        let env = FakeEnvironment(cachedSamples: [sample("Home", known: true)])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)

        model.setPower(false)
        #expect(model.displayedPower == false)

        // Stale event from before setPower(false) ran must not flip the switch back on.
        env.send(.interface(InterfaceState(powerOn: true, ssid: "Home", rssi: -50)))
        await drainMainActor()
        #expect(model.displayedPower == false)

        // Settled powerChanged clears pendingPower.
        env.send(.powerChanged(InterfaceState(powerOn: false, ssid: nil, rssi: nil)))
        await drainMainActor()
        #expect(model.pendingPower == nil)
        #expect(model.displayedPower == false)
        #expect(model.mode == .wifiOff)

        // Turning power back on while open triggers cache refresh + scan.
        let scansBefore = env.scanCount
        env.send(.powerChanged(InterfaceState(powerOn: true, ssid: nil, rssi: nil)))
        await drainMainActor()
        #expect(env.refreshCacheCount == 1)
        #expect(env.scanCount == scansBefore + 1)
    }

    @Test func locationPermissionTransitionWhileOpenRefreshesAndScans() async {
        let env = FakeEnvironment(initialLocationAccess: .denied, cachedSamples: [])
        let model = PickerModel(environment: env, clock: TestClock().makeClock())
        #expect(await model.open().value)
        #expect(model.mode == .locationNeeded(.denied))
        #expect(env.scanCount == 0)

        env.send(.locationAccess(.granted))
        await drainMainActor()
        #expect(model.mode == .networks)
        #expect(env.refreshCacheCount == 1)
        #expect(env.scanCount == 1)
    }

    @Test func dimmingClockAdvancesAndBlocksActivationOfDimmedCells() async throws {
        let clock = TestClock()
        let env = FakeEnvironment(cachedSamples: [sample("Fading", secure: false)])
        let model = PickerModel(environment: env, clock: clock.makeClock())
        #expect(await model.open().value)
        #expect(try #require(model.cell(for: "Fading")).dimmed == false)

        clock.advance(by: PickerSession.dimInterval)
        await drainMainActor()
        #expect(try #require(model.cell(for: "Fading")).dimmed)

        model.activate("Fading")
        #expect(env.joins.isEmpty)
        model.close()
    }
}
