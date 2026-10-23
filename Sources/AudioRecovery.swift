// Audio route recovery support for IOGuard — Author: djred.

import CoreAudio
import Foundation

struct AudioRouteRecoveryDeviceInfo {
    let identifier: AudioDeviceID
    let uid: String?
    let name: String
    let isAlive: Bool
    let hasOutputStreams: Bool
    let transportType: UInt32?
    let masterMuteReadable: Bool
    let masterMuteSettable: Bool
}

struct AudioRouteRecoveryBackend {
    let deviceIDs: () -> [AudioDeviceID]
    let currentDefaultOutput: () -> AudioDeviceID?
    let currentSystemOutput: () -> AudioDeviceID?
    let deviceInfo: (AudioDeviceID) -> AudioRouteRecoveryDeviceInfo?
    let readMasterMute: (AudioDeviceID) -> Bool?
    let setMasterMute: (AudioDeviceID, Bool) -> Bool
    let setDefaultOutput: (AudioDeviceID) -> Bool
}

protocol AudioRouteRecoveryScheduling: AnyObject {
    var uptime: TimeInterval { get }
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AudioRouteRecoveryScheduleToken
}

final class AudioRouteRecoveryScheduleToken {
    private var cancelAction: (() -> Void)?

    init(cancel: @escaping () -> Void = {}) {
        cancelAction = cancel
    }

    func cancel() {
        let action = cancelAction
        cancelAction = nil
        action?()
    }
}

private final class MainQueueAudioRouteRecoveryScheduler: AudioRouteRecoveryScheduling {
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AudioRouteRecoveryScheduleToken {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
        return AudioRouteRecoveryScheduleToken { work.cancel() }
    }
}

final class AudioRouteRecovery {
    private struct Session {
        let reason: String
        let preferredUID: String
        let fallbackUID: String
        let fallbackOriginalMute: Bool
        let originalSystemOutputUID: String?
    }

    private let preferredOutput: () -> AudioDeviceID?
    private let canRecover: () -> Bool
    private let report: (String) -> Void
    private let backend: AudioRouteRecoveryBackend
    private let scheduler: AudioRouteRecoveryScheduling

    private var pendingPreflight: AudioRouteRecoveryScheduleToken?
    private var pendingReturn: AudioRouteRecoveryScheduleToken?
    private var pendingCleanup: AudioRouteRecoveryScheduleToken?
    private var session: Session?
    private var recovering = false
    private var lastAttempt: TimeInterval?

    var isRecovering: Bool {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        return recovering
    }

    init(
        preferredOutput: @escaping () -> AudioDeviceID?,
        canRecover: @escaping () -> Bool,
        report: @escaping (String) -> Void
    ) {
        self.preferredOutput = preferredOutput
        self.canRecover = canRecover
        self.report = report
        self.backend = Self.arCoreAudioBackend()
        self.scheduler = MainQueueAudioRouteRecoveryScheduler()
    }

    // Internal injection points keep the recovery state machine deterministic in tests.
    init(
        preferredOutput: @escaping () -> AudioDeviceID?,
        canRecover: @escaping () -> Bool,
        report: @escaping (String) -> Void,
        backend: AudioRouteRecoveryBackend,
        scheduler: AudioRouteRecoveryScheduling
    ) {
        self.preferredOutput = preferredOutput
        self.canRecover = canRecover
        self.report = report
        self.backend = backend
        self.scheduler = scheduler
    }

    func request(reason: String, automatic: Bool = true) {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        guard !recovering, session == nil else { return }

        let now = scheduler.uptime
        let cooldown = automatic ? 60.0 : 5.0
        if let lastAttempt, now - lastAttempt < cooldown { return }

        // Every new automatic event restarts the settle window. A manual request
        // takes over a pending automatic preflight and runs immediately.
        pendingPreflight?.cancel()
        pendingPreflight = nil
        if automatic {
            pendingPreflight = scheduler.schedule(after: 2) { [weak self] in
                guard let self else { return }
                self.pendingPreflight = nil
                self.arBegin(reason: reason)
            }
        } else {
            arBegin(reason: reason)
        }
    }

    func cancel() {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        if let pendingPreflight {
            pendingPreflight.cancel()
            self.pendingPreflight = nil
            return
        }
        guard session != nil else { return }
        pendingReturn?.cancel()
        pendingReturn = nil
        arAttemptReturn(attempt: 0, cancellation: true)
    }

    private func arBegin(reason: String) {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        guard canRecover() else {
            report("Audio recovery skipped for \(reason): recovery is disabled.")
            return
        }
        guard let preferredID = preferredOutput(),
              let preferredInfo = backend.deviceInfo(preferredID),
              preferredInfo.isAlive,
              preferredInfo.hasOutputStreams,
              let preferredUID = preferredInfo.uid,
              !preferredUID.isEmpty else {
            report("Audio recovery skipped for \(reason): the preferred output is missing, unavailable, or has no output streams.")
            return
        }
        guard backend.currentDefaultOutput() == preferredID else {
            report("Audio recovery skipped for \(reason): the current default output no longer matches the preferred output.")
            return
        }

        let candidates = Set(backend.deviceIDs()).compactMap { identifier -> (AudioRouteRecoveryDeviceInfo, Bool)? in
            guard identifier != preferredID,
                  let info = backend.deviceInfo(identifier),
                  arIsEligibleFallback(info),
                  let originalMute = backend.readMasterMute(identifier) else { return nil }
            return (info, originalMute)
        }
        guard candidates.count == 1, let (fallback, originalMute) = candidates.first,
              let fallbackUID = fallback.uid, !fallbackUID.isEmpty else {
            report("Audio recovery skipped for \(reason): expected exactly one eligible built-in fallback with a readable, settable master mute.")
            return
        }

        lastAttempt = scheduler.uptime

        let originalSystemOutputUID = backend.currentSystemOutput()
            .flatMap { backend.deviceInfo($0)?.uid }
        session = Session(
            reason: reason,
            preferredUID: preferredUID,
            fallbackUID: fallbackUID,
            fallbackOriginalMute: originalMute,
            originalSystemOutputUID: originalSystemOutputUID
        )
        recovering = true

        let muteWriteSucceeded = backend.setMasterMute(fallback.identifier, true)
        guard muteWriteSucceeded, backend.readMasterMute(fallback.identifier) == true else {
            arFinish(success: false, detail: "the built-in fallback could not be muted and verified")
            return
        }

        _ = backend.setDefaultOutput(fallback.identifier)
        guard arCurrentOutputMatches(uid: fallbackUID) else {
            arFinish(success: false, detail: "the built-in fallback did not become the verified default output")
            return
        }

        pendingReturn = scheduler.schedule(after: 0.35) { [weak self] in
            guard let self else { return }
            self.pendingReturn = nil
            self.arAttemptReturn(attempt: 0, cancellation: false)
        }
    }

    private func arAttemptReturn(attempt: Int, cancellation: Bool) {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        guard let session else { return }
        guard let preferredID = arResolveAliveOutput(uid: session.preferredUID) else {
            arRetryOrFinish(
                attempt: attempt,
                cancellation: cancellation,
                detail: "the original preferred output is no longer available by UID"
            )
            return
        }

        // Restore only the output default. Input and system-output defaults are never written.
        _ = backend.setDefaultOutput(preferredID)
        let outputRestored = arCurrentOutputMatches(uid: session.preferredUID)
        let systemOutputRestored = arSystemOutputMatchesSnapshot(session.originalSystemOutputUID)
        if outputRestored && systemOutputRestored != false {
            let detail = systemOutputRestored == nil
                ? "the preferred output was restored; the original system-output default could not be verified"
                : "the preferred output was restored"
            arFinish(success: true, detail: detail)
            return
        }

        let detail: String
        if !outputRestored {
            detail = "the preferred output did not verify after the return attempt"
        } else {
            detail = "the system-output default changed and could not be verified as its original device"
        }
        arRetryOrFinish(attempt: attempt, cancellation: cancellation, detail: detail)
    }

    private func arRetryOrFinish(attempt: Int, cancellation: Bool, detail: String) {
        if attempt == 0 {
            pendingReturn = scheduler.schedule(after: 0.5) { [weak self] in
                guard let self else { return }
                self.pendingReturn = nil
                self.arAttemptReturn(attempt: 1, cancellation: cancellation)
            }
        } else {
            arFinish(success: false, detail: "\(detail) after one retry")
        }
    }

    private func arFinish(success: Bool, detail: String) {
        precondition(Thread.isMainThread, "AudioRouteRecovery is main-thread only")
        guard let session else { return }
        pendingReturn?.cancel()
        pendingReturn = nil

        var finalSuccess = success
        var finalDetail = detail
        if arDefinitelyOffFallback(uid: session.fallbackUID) {
            if let fallbackID = arResolveAliveOutput(uid: session.fallbackUID) {
                let muteRestored = backend.setMasterMute(fallbackID, session.fallbackOriginalMute)
                    && backend.readMasterMute(fallbackID) == session.fallbackOriginalMute
                if !muteRestored {
                    finalSuccess = false
                    finalDetail += "; the fallback's original mute state could not be verified"
                }
            } else {
                finalSuccess = false
                finalDetail += "; the fallback's original mute state could not be restored because that device is unavailable"
            }
        } else {
            finalSuccess = false
            finalDetail += "; the fallback remains muted because the current output is still on it or cannot be verified"
        }

        if finalSuccess {
            report("Audio recovery for \(session.reason) completed: \(finalDetail).")
        } else {
            report("Audio recovery for \(session.reason) failed: \(finalDetail).")
        }
        self.session = nil
        arScheduleCleanup()
    }

    private func arScheduleCleanup() {
        pendingCleanup?.cancel()
        pendingCleanup = scheduler.schedule(after: 0.2) { [weak self] in
            guard let self else { return }
            self.pendingCleanup = nil
            self.recovering = false
        }
    }

    private func arIsEligibleFallback(_ info: AudioRouteRecoveryDeviceInfo) -> Bool {
        guard info.isAlive,
              info.hasOutputStreams,
              info.transportType == kAudioDeviceTransportTypeBuiltIn,
              info.masterMuteReadable,
              info.masterMuteSettable,
              let uid = info.uid, !uid.isEmpty else { return false }
        return !Self.arLooksLikeExternalDisplayOrWirelessDevice(info.name)
    }

    private func arResolveAliveOutput(uid: String) -> AudioDeviceID? {
        let matches = Set(backend.deviceIDs()).compactMap { identifier -> AudioDeviceID? in
            guard let info = backend.deviceInfo(identifier),
                  info.uid == uid,
                  info.isAlive,
                  info.hasOutputStreams else { return nil }
            return identifier
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func arCurrentOutputMatches(uid: String) -> Bool {
        guard let identifier = backend.currentDefaultOutput(),
              let info = backend.deviceInfo(identifier) else { return false }
        return info.uid == uid && info.isAlive && info.hasOutputStreams
    }

    private func arDefinitelyOffFallback(uid: String) -> Bool {
        // An unreadable default is treated as unsafe: keep the fallback muted.
        guard let current = backend.currentDefaultOutput(),
              let info = backend.deviceInfo(current),
              let currentUID = info.uid else { return false }
        return currentUID != uid
    }

    private func arSystemOutputMatchesSnapshot(_ uid: String?) -> Bool? {
        guard let uid else { return nil }
        guard let identifier = backend.currentSystemOutput(),
              let info = backend.deviceInfo(identifier) else { return false }
        return info.uid == uid && info.isAlive && info.hasOutputStreams
    }

    private static func arLooksLikeExternalDisplayOrWirelessDevice(_ name: String) -> Bool {
        let normalized = name.lowercased()
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        return normalized.contains("hdmi")
            || normalized.contains("bluetooth")
            || normalized.contains("airplay")
            || normalized.contains("television")
            || normalized.contains("roku")
            || normalized.contains("appletv")
            || tokens.contains("tv")
    }

    private static func arCoreAudioBackend() -> AudioRouteRecoveryBackend {
        AudioRouteRecoveryBackend(
            deviceIDs: { arReadDeviceIDs() },
            currentDefaultOutput: { arReadSystemDevice(kAudioHardwarePropertyDefaultOutputDevice) },
            currentSystemOutput: { arReadSystemDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) },
            deviceInfo: { arReadDeviceInfo($0) },
            readMasterMute: { arReadMasterMute($0) },
            setMasterMute: { arSetMasterMute($0, muted: $1) },
            setDefaultOutput: { arSetSystemDevice(kAudioHardwarePropertyDefaultOutputDevice, device: $0) }
        )
    }

    private static func arAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func arReadDeviceIDs() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = arAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var identifiers = [AudioDeviceID](repeating: 0, count: count)
        let status = identifiers.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, baseAddress)
        }
        return status == noErr ? identifiers : []
    }

    private static func arReadSystemDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = arAddress(selector)
        var identifier: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &identifier)
        return status == noErr && identifier != 0 ? identifier : nil
    }

    private static func arReadDeviceInfo(_ identifier: AudioDeviceID) -> AudioRouteRecoveryDeviceInfo? {
        let alive = arReadUInt32(identifier, selector: kAudioDevicePropertyDeviceIsAlive) == 1
        let transport = arReadUInt32(identifier, selector: kAudioDevicePropertyTransportType)
        let uid = arReadCFString(identifier, selector: kAudioDevicePropertyDeviceUID)
        let name = arReadCFString(identifier, selector: kAudioObjectPropertyName) ?? "Unknown device"
        var outputAddress = arAddress(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var outputSize: UInt32 = 0
        let hasOutputStreams = AudioObjectGetPropertyDataSize(identifier, &outputAddress, 0, nil, &outputSize) == noErr && outputSize > 0

        var muteAddress = arAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var muteSettable: DarwinBoolean = false
        let muteReadable = AudioObjectHasProperty(identifier, &muteAddress)
        let muteSettableStatus = AudioObjectIsPropertySettable(identifier, &muteAddress, &muteSettable)
        let canSetMute = muteSettableStatus == noErr && muteSettable.boolValue

        return AudioRouteRecoveryDeviceInfo(
            identifier: identifier,
            uid: uid,
            name: name,
            isAlive: alive,
            hasOutputStreams: hasOutputStreams,
            transportType: transport,
            masterMuteReadable: muteReadable,
            masterMuteSettable: canSetMute
        )
    }

    private static func arReadUInt32(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = arAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func arReadCFString(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = arAddress(selector)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String : nil
    }

    private static func arReadMasterMute(_ identifier: AudioDeviceID) -> Bool? {
        var address = arAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    private static func arSetMasterMute(_ identifier: AudioDeviceID, muted: Bool) -> Bool {
        var address = arAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            identifier,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        ) == noErr
    }

    private static func arSetSystemDevice(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = arAddress(selector)
        var identifier = device
        return AudioObjectSetPropertyData(
            system,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &identifier
        ) == noErr
    }
}
