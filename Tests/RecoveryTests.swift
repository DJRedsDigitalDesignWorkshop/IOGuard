import CoreAudio
import Foundation

private final class TestRecoveryScheduler: AudioRouteRecoveryScheduling {
    private struct Entry {
        let deadline: TimeInterval
        let action: () -> Void
        var cancelled: Bool
    }

    private var nextID = 0
    private var entries: [Int: Entry] = [:]
    private(set) var uptime: TimeInterval = 0

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AudioRouteRecoveryScheduleToken {
        nextID += 1
        let identifier = nextID
        entries[identifier] = Entry(deadline: uptime + max(0, delay), action: action, cancelled: false)
        return AudioRouteRecoveryScheduleToken { [weak self] in
            self?.entries[identifier]?.cancelled = true
        }
    }

    func advance(by interval: TimeInterval) {
        let target = uptime + interval
        while let next = entries
            .filter({ !$0.value.cancelled && $0.value.deadline <= target })
            .min(by: { $0.value.deadline < $1.value.deadline }) {
            entries[next.key] = nil
            uptime = next.value.deadline
            next.value.action()
        }
        entries = entries.filter { !$0.value.cancelled }
        uptime = target
    }
}

private final class FakeAudioState {
    var devices: [AudioDeviceID: AudioRouteRecoveryDeviceInfo] = [:]
    var defaultOutput: AudioDeviceID?
    var systemOutput: AudioDeviceID?
    var muteStates: [AudioDeviceID: Bool] = [:]
    var writes: [String] = []
    var rejectedOutputWrites: Set<AudioDeviceID> = []
    var rejectedUnmuteWrites: Set<AudioDeviceID> = []
    var defaultOutputReadSequence: [AudioDeviceID?] = []

    func backend() -> AudioRouteRecoveryBackend {
        AudioRouteRecoveryBackend(
            deviceIDs: { Array(self.devices.keys).sorted() },
            currentDefaultOutput: {
                if !self.defaultOutputReadSequence.isEmpty {
                    return self.defaultOutputReadSequence.removeFirst()
                }
                return self.defaultOutput
            },
            currentSystemOutput: { self.systemOutput },
            deviceInfo: { self.devices[$0] },
            readMasterMute: { self.muteStates[$0] },
            setMasterMute: { identifier, muted in
                self.writes.append("mute:\(identifier):\(muted)")
                guard muted || !self.rejectedUnmuteWrites.contains(identifier) else { return false }
                self.muteStates[identifier] = muted
                return true
            },
            setDefaultOutput: { identifier in
                self.writes.append("output:\(identifier)")
                guard !self.rejectedOutputWrites.contains(identifier) else { return false }
                self.defaultOutput = identifier
                return true
            }
        )
    }

    func add(
        _ identifier: AudioDeviceID,
        uid: String,
        name: String,
        alive: Bool = true,
        hasOutput: Bool = true,
        transport: UInt32,
        muteReadable: Bool = true,
        muteSettable: Bool = true,
        muted: Bool = false
    ) {
        devices[identifier] = AudioRouteRecoveryDeviceInfo(
            identifier: identifier,
            uid: uid,
            name: name,
            isAlive: alive,
            hasOutputStreams: hasOutput,
            transportType: transport,
            masterMuteReadable: muteReadable,
            masterMuteSettable: muteSettable
        )
        muteStates[identifier] = muted
    }
}

@main
private enum RecoveryTests {
    static func main() {
        testManualImmediateAndCooldown()
        testAutomaticSettleAndCooldown()
        testAutomaticPreflightDebouncesAndDoesNotConsumeCooldownOnFailure()
        testCrossModeCooldowns()
        testMissingPreferredOutput()
        testSafeFallbackEligibilityAndUniqueness()
        testPreferredDeviceResolvesByUIDAfterReconnect()
        testFailedReturnKeepsSelectedFallbackMuted()
        testCleanupFailureOverridesSuccess()
        testCancellation()
        print("PASS: AudioRouteRecovery deterministic tests")
    }

    private static func testManualImmediateAndCooldown() {
        let state = standardState()
        let scheduler = TestRecoveryScheduler()
        let messages = MessageBox()
        let recovery = makeRecovery(state, scheduler: scheduler, messages: messages)

        recovery.request(reason: "manual check", automatic: false)
        expect(recovery.isRecovering, "manual recovery should start immediately")
        expect(state.defaultOutput == 20, "manual recovery should select the fallback")
        expect(state.writes.count >= 2 && state.writes[0] == "mute:20:true" && state.writes[1] == "output:20", "fallback must be muted and verified before selection")
        expect(state.systemOutput == 10, "recovery must leave system output unchanged")

        scheduler.advance(by: 0.35)
        expect(state.defaultOutput == 10, "preferred output should be restored after the short detour")
        expect(state.muteStates[20] == false, "fallback mute should return to its original state")
        expect(recovery.isRecovering, "self-write suppression should include the cleanup drain")
        scheduler.advance(by: 0.2)
        expect(!recovery.isRecovering, "recovery should finish after the cleanup drain")

        let writeCount = state.writes.count
        recovery.request(reason: "manual cooldown", automatic: false)
        expect(state.writes.count == writeCount, "manual recovery should be suppressed during its five-second cooldown")
        scheduler.advance(by: 4.45)
        recovery.request(reason: "manual after cooldown", automatic: false)
        expect(state.defaultOutput == 20, "manual recovery should be allowed when its cooldown expires")
        recovery.cancel()
        expect(state.defaultOutput == 10, "cancelling an in-flight recovery should return the preferred output immediately")
        expect(state.muteStates[20] == false, "in-flight cancellation should restore the fallback mute state")
        scheduler.advance(by: 0.2)
        expect(!recovery.isRecovering, "cancelled recovery should drain its writes")
    }

    private static func testAutomaticSettleAndCooldown() {
        let state = standardState()
        let scheduler = TestRecoveryScheduler()
        let recovery = makeRecovery(state, scheduler: scheduler)

        recovery.request(reason: "automatic drift")
        expect(state.writes.isEmpty, "automatic recovery should wait for the settle interval")
        scheduler.advance(by: 1.99)
        expect(state.writes.isEmpty, "automatic recovery must not start before two seconds")
        scheduler.advance(by: 0.01)
        expect(state.defaultOutput == 20, "automatic recovery should start after two seconds")
        scheduler.advance(by: 0.35)
        scheduler.advance(by: 0.2)
        expect(state.defaultOutput == 10 && !recovery.isRecovering, "automatic recovery should restore and finish")

        let writeCount = state.writes.count
        recovery.request(reason: "automatic cooldown")
        scheduler.advance(by: 59.45)
        expect(state.writes.count == writeCount, "automatic recovery should be suppressed before its sixty-second cooldown expires")
        recovery.request(reason: "automatic after cooldown")
        scheduler.advance(by: 2)
        expect(state.defaultOutput == 20, "automatic recovery should be allowed at the cooldown boundary")
        recovery.cancel()
        scheduler.advance(by: 0.2)
    }

    private static func testAutomaticPreflightDebouncesAndDoesNotConsumeCooldownOnFailure() {
        let burstState = standardState()
        let burstScheduler = TestRecoveryScheduler()
        let burstRecovery = makeRecovery(burstState, scheduler: burstScheduler)
        burstRecovery.request(reason: "first topology event")
        burstScheduler.advance(by: 1.5)
        burstRecovery.request(reason: "last topology event")
        burstScheduler.advance(by: 1.99)
        expect(burstState.writes.isEmpty, "a new automatic event should restart the two-second settle window")
        burstScheduler.advance(by: 0.01)
        expect(burstState.defaultOutput == 20, "the debounced automatic request should begin after the last event settles")
        burstRecovery.cancel()
        burstScheduler.advance(by: 0.2)

        let retryState = standardState()
        retryState.defaultOutput = 20
        let retryScheduler = TestRecoveryScheduler()
        let retryRecovery = makeRecovery(retryState, scheduler: retryScheduler)
        retryRecovery.request(reason: "preflight mismatch")
        retryScheduler.advance(by: 2)
        expect(retryState.writes.isEmpty, "a mismatched current output should fail preflight without writes")
        retryState.defaultOutput = 10
        retryRecovery.request(reason: "valid event after failed preflight")
        retryScheduler.advance(by: 2)
        expect(retryState.defaultOutput == 20, "a failed preflight should not consume the automatic cooldown")
        retryRecovery.cancel()
        retryScheduler.advance(by: 0.2)
    }

    private static func testCrossModeCooldowns() {
        let afterManual = standardState()
        let manualScheduler = TestRecoveryScheduler()
        let manualRecovery = makeRecovery(afterManual, scheduler: manualScheduler)
        manualRecovery.request(reason: "manual attempt", automatic: false)
        manualRecovery.cancel()
        manualScheduler.advance(by: 0.2)
        let manualWriteCount = afterManual.writes.count
        manualRecovery.request(reason: "automatic after manual")
        manualScheduler.advance(by: 3)
        expect(afterManual.writes.count == manualWriteCount, "an automatic request should honor the sixty-second cooldown after a manual attempt")

        let afterAutomatic = standardState()
        let automaticScheduler = TestRecoveryScheduler()
        let automaticRecovery = makeRecovery(afterAutomatic, scheduler: automaticScheduler)
        automaticRecovery.request(reason: "automatic attempt")
        automaticScheduler.advance(by: 2)
        automaticRecovery.cancel()
        automaticScheduler.advance(by: 0.2)
        let automaticWriteCount = afterAutomatic.writes.count
        automaticRecovery.request(reason: "manual inside cooldown", automatic: false)
        expect(afterAutomatic.writes.count == automaticWriteCount, "a manual request should honor the five-second cooldown after an automatic attempt")
        automaticScheduler.advance(by: 4.8)
        automaticRecovery.request(reason: "manual after cooldown", automatic: false)
        expect(afterAutomatic.defaultOutput == 20, "a manual request should be allowed after five seconds from an automatic attempt")
        automaticRecovery.cancel()
        automaticScheduler.advance(by: 0.2)
    }

    private static func testMissingPreferredOutput() {
        let state = standardState()
        let scheduler = TestRecoveryScheduler()
        let messages = MessageBox()
        let recovery = AudioRouteRecovery(
            preferredOutput: { nil },
            canRecover: { true },
            report: { messages.values.append($0) },
            backend: state.backend(),
            scheduler: scheduler
        )
        recovery.request(reason: "missing preference", automatic: false)
        expect(state.writes.isEmpty, "missing preferred output must not write Core Audio properties")
        expect(!recovery.isRecovering, "missing preferred output should not enter recovery")
        expect(messages.values.contains(where: { $0.contains("preferred output is missing") }), "missing preferred output should be reported")
    }

    private static func testSafeFallbackEligibilityAndUniqueness() {
        let state = standardState()
        state.add(30, uid: "hdmi", name: "Built-in HDMI TV", transport: kAudioDeviceTransportTypeBuiltIn)
        state.add(31, uid: "bluetooth", name: "Bluetooth Speakers", transport: kAudioDeviceTransportTypeBuiltIn)
        state.add(32, uid: "usb", name: "USB Speakers", transport: kAudioDeviceTransportTypeUSB)
        state.add(33, uid: "dead", name: "Dead Speakers", alive: false, transport: kAudioDeviceTransportTypeBuiltIn)
        state.add(34, uid: "input-only", name: "Input-only device", hasOutput: false, transport: kAudioDeviceTransportTypeBuiltIn)
        state.add(35, uid: "mute-locked", name: "Mute-locked device", transport: kAudioDeviceTransportTypeBuiltIn, muteSettable: false)
        let scheduler = TestRecoveryScheduler()
        let recovery = makeRecovery(state, scheduler: scheduler)

        recovery.request(reason: "safe candidate", automatic: false)
        expect(state.defaultOutput == 20, "only the one eligible internal output should be selected")
        recovery.cancel()
        scheduler.advance(by: 0.2)

        let ambiguous = standardState()
        ambiguous.add(36, uid: "second-internal", name: "Internal Speakers 2", transport: kAudioDeviceTransportTypeBuiltIn)
        let ambiguousRecovery = makeRecovery(ambiguous, scheduler: TestRecoveryScheduler())
        ambiguousRecovery.request(reason: "ambiguous candidates", automatic: false)
        expect(ambiguous.writes.isEmpty, "multiple eligible built-in outputs should abort without writes")

        let originallyMuted = standardState()
        originallyMuted.muteStates[20] = true
        let mutedScheduler = TestRecoveryScheduler()
        let mutedRecovery = makeRecovery(originallyMuted, scheduler: mutedScheduler)
        mutedRecovery.request(reason: "preserve muted fallback", automatic: false)
        expect(originallyMuted.defaultOutput == 20, "an otherwise safe fallback should remain eligible when originally muted")
        mutedScheduler.advance(by: 0.35)
        expect(originallyMuted.muteStates[20] == true, "cleanup should preserve the fallback's original muted state")
        mutedScheduler.advance(by: 0.2)
    }

    private static func testFailedReturnKeepsSelectedFallbackMuted() {
        let state = standardState()
        state.rejectedOutputWrites.insert(10)
        let scheduler = TestRecoveryScheduler()
        let messages = MessageBox()
        let recovery = makeRecovery(state, scheduler: scheduler, messages: messages)

        recovery.request(reason: "return failure", automatic: false)
        scheduler.advance(by: 0.35)
        expect(state.defaultOutput == 20, "failed return attempt should leave the fallback selected")
        scheduler.advance(by: 0.5)
        expect(state.defaultOutput == 20, "the single retry should be bounded")
        expect(state.muteStates[20] == true, "a selected fallback must remain muted after failed return")
        expect(messages.values.contains(where: { $0.contains("fallback remains muted") }), "unsafe cleanup should be reported explicitly")
        expect(recovery.isRecovering, "failed recovery should remain suppressed through cleanup")
        scheduler.advance(by: 0.2)
        expect(!recovery.isRecovering, "failed recovery should eventually finish its cleanup drain")
    }

    private static func testPreferredDeviceResolvesByUIDAfterReconnect() {
        let state = standardState()
        let scheduler = TestRecoveryScheduler()
        let messages = MessageBox()
        let recovery = makeRecovery(state, scheduler: scheduler, messages: messages)

        recovery.request(reason: "preferred reconnect", automatic: false)
        state.devices[10] = nil
        state.muteStates[10] = nil
        state.add(11, uid: "preferred-uid", name: "Universal Audio", transport: kAudioDeviceTransportTypeUSB)
        state.systemOutput = 11
        scheduler.advance(by: 0.35)

        expect(state.defaultOutput == 11, "return should resolve the preferred device by UID after its device ID changes")
        expect(state.muteStates[20] == false, "the fallback should be unmuted after UID-based restoration")
        expect(messages.values.contains(where: { $0.contains("completed") }), "UID-based restoration should report success")
        scheduler.advance(by: 0.2)
    }

    private static func testCleanupFailureOverridesSuccess() {
        let state = standardState()
        state.rejectedUnmuteWrites.insert(20)
        let scheduler = TestRecoveryScheduler()
        let messages = MessageBox()
        let recovery = makeRecovery(state, scheduler: scheduler, messages: messages)

        recovery.request(reason: "mute cleanup failure", automatic: false)
        scheduler.advance(by: 0.35)
        let finalMuteFailureStatus = messages.values.last ?? ""
        expect(state.defaultOutput == 10, "preferred output should still return when fallback unmute cleanup fails")
        expect(state.muteStates[20] == true, "failed cleanup must leave the fallback safely muted")
        expect(finalMuteFailureStatus.contains("failed") && finalMuteFailureStatus.contains("original mute state could not be verified"), "mute cleanup failure must appear in the final failed status")
        expect(!finalMuteFailureStatus.contains("completed"), "mute cleanup failure must not leave a completed status")
        scheduler.advance(by: 0.2)

        let uncertain = standardState()
        uncertain.defaultOutputReadSequence = [10, 20, 10, nil]
        let uncertainScheduler = TestRecoveryScheduler()
        let uncertainMessages = MessageBox()
        let uncertainRecovery = makeRecovery(uncertain, scheduler: uncertainScheduler, messages: uncertainMessages)
        uncertainRecovery.request(reason: "uncertain cleanup output", automatic: false)
        uncertainScheduler.advance(by: 0.35)
        let finalUncertainStatus = uncertainMessages.values.last ?? ""
        expect(uncertain.muteStates[20] == true, "an unverifiable current output must keep the fallback muted")
        expect(finalUncertainStatus.contains("failed") && finalUncertainStatus.contains("cannot be verified"), "an unverifiable off-fallback check must force a final failed status")
        expect(!finalUncertainStatus.contains("completed"), "an unverifiable off-fallback check must not leave a completed status")
        uncertainScheduler.advance(by: 0.2)
    }

    private static func testCancellation() {
        let paused = standardState()
        let pausedScheduler = TestRecoveryScheduler()
        let pausedRecovery = makeRecovery(paused, scheduler: pausedScheduler)
        pausedRecovery.request(reason: "paused automatic request")
        pausedRecovery.cancel()
        pausedScheduler.advance(by: 3)
        expect(paused.writes.isEmpty, "cancelling a pending automatic preflight should prevent all writes")
        expect(!pausedRecovery.isRecovering, "cancelling a preflight should leave recovery idle")
    }

    private static func standardState() -> FakeAudioState {
        let state = FakeAudioState()
        state.add(10, uid: "preferred-uid", name: "Universal Audio", transport: kAudioDeviceTransportTypeUSB)
        state.add(20, uid: "builtin-uid", name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn)
        state.defaultOutput = 10
        state.systemOutput = 10
        return state
    }

    private static func makeRecovery(
        _ state: FakeAudioState,
        scheduler: TestRecoveryScheduler,
        messages: MessageBox = MessageBox()
    ) -> AudioRouteRecovery {
        AudioRouteRecovery(
            preferredOutput: { 10 },
            canRecover: { true },
            report: { messages.values.append($0) },
            backend: state.backend(),
            scheduler: scheduler
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}

private final class MessageBox {
    var values: [String] = []
}
