// Universal Audio Guard 1.0.3 — djred
import Foundation
import AppKit
import CoreGraphics
// Ignore a premature manual request until the dispatch handler and readiness file exist.
signal(SIGUSR1, SIG_IGN)
import CoreAudio

let system = AudioObjectID(kAudioObjectSystemObject)
func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func devices() -> [AudioDeviceID] {
    var a = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
    var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard !result.isEmpty else { return [] }
    let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &a, 0, nil, &size, $0.baseAddress!) }
    return status == noErr ? result : []
}
func name(_ device: AudioDeviceID) -> String {
    var a = address(kAudioObjectPropertyName)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &a, 0, nil, &size, $0) }
    guard status == noErr else { return "" }
    return value as String
}
func supports(_ device: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
    var a = address(kAudioDevicePropertyStreams, scope)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr && size > 0
}
let target = ProcessInfo.processInfo.environment["UA_DEVICE_NAME"] ?? "Universal Audio Thunderbolt"
let timingTest = CommandLine.arguments.contains("--self-test-timing")
var testEnforcementCount = 0
var routeRecovery: AudioRouteRecovery?
func enforce() {
    if timingTest { testEnforcementCount += 1; return }
    guard routeRecovery?.isRecovering != true else { return }
    let matches = devices().filter { name($0).caseInsensitiveCompare(target) == .orderedSame }
    for (selector, scope) in [(kAudioHardwarePropertyDefaultInputDevice, kAudioDevicePropertyScopeInput), (kAudioHardwarePropertyDefaultOutputDevice, kAudioDevicePropertyScopeOutput), (kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioDevicePropertyScopeOutput)] {
        let candidates = matches.filter { supports($0, scope) }
        guard candidates.count == 1 else { continue }
        var desired = candidates[0]
        var current: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(selector)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &current) == noErr, current != desired else { continue }
        let status = AudioObjectSetPropertyData(system, &a, 0, nil, size, &desired)
        if status != noErr { fputs("Unable to restore \(target): Core Audio error \(status)\n", stderr) }
    }
}
if CommandLine.arguments.contains("--version") { print("Universal Audio Guard 1.0.3"); exit(0) }
if CommandLine.arguments.contains("--list") {
    for d in devices() { print("\(name(d)) | input=\(supports(d, kAudioDevicePropertyScopeInput)) output=\(supports(d, kAudioDevicePropertyScopeOutput))") }
    exit(0)
}
if CommandLine.arguments.contains("--once") { enforce(); exit(0) }
let queue = DispatchQueue.main
var pending: DispatchWorkItem?
func scheduleRestore() {
    guard routeRecovery?.isRecovering != true else { return }
    pending?.cancel()
    let work = DispatchWorkItem {
        pending = nil
        enforce()
    }
    pending = work
    // Let clients finish adopting the new device before restoring the preferred one.
    queue.asyncAfter(deadline: .now() + 1.0, execute: work)
}
func retryIfIdle() {
    guard pending == nil, routeRecovery?.isRecovering != true else { return }
    enforce()
}
if timingTest {
    scheduleRestore()
    queue.asyncAfter(deadline: .now() + 0.2) {
        retryIfIdle()
        guard testEnforcementCount == 0 else { fputs("FAIL: fallback bypassed delay\n", stderr); exit(1) }
    }
    queue.asyncAfter(deadline: .now() + 0.4) { scheduleRestore() }
    queue.asyncAfter(deadline: .now() + 0.9) {
        retryIfIdle()
        guard testEnforcementCount == 0 else { fputs("FAIL: reset debounce bypassed\n", stderr); exit(1) }
    }
    queue.asyncAfter(deadline: .now() + 1.8) {
        guard testEnforcementCount == 1, pending == nil else { fputs("FAIL: delayed restoration did not complete once\n", stderr); exit(1) }
        retryIfIdle()
        guard testEnforcementCount == 2 else { fputs("FAIL: idle retry did not resume\n", stderr); exit(1) }
        print("PASS: fallback respects delay, notifications debounce, idle retry resumes")
        exit(0)
    }
    RunLoop.main.run()
    exit(1)
}
func preferredOutput() -> AudioDeviceID? {
    let candidates = devices().filter { name($0).caseInsensitiveCompare(target) == .orderedSame && supports($0, kAudioDevicePropertyScopeOutput) }
    return candidates.count == 1 ? candidates[0] : nil
}
func currentOutput() -> AudioDeviceID? {
    var a = address(kAudioHardwarePropertyDefaultOutputDevice)
    var value: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectGetPropertyData(system, &a, 0, nil, &size, &value) == noErr ? value : nil
}
func outputTopology() -> Set<String> {
    Set(devices().filter { supports($0, kAudioDevicePropertyScopeOutput) }.compactMap { device in
        var a = address(kAudioDevicePropertyDeviceUID)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &a, 0, nil, &size, $0) }
        return status == noErr ? value as String : nil
    })
}
let autoRecoveryEnabled = ProcessInfo.processInfo.environment["IOGUARD_AUTO_RECOVER"] != "0"
routeRecovery = AudioRouteRecovery(preferredOutput: preferredOutput, canRecover: { true }, report: { message in
    fputs("IOGuard: \(message)\n", stderr)
})
var lastOutputTopology = outputTopology()
for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDevices] {
    var a = address(selector)
    let status = AudioObjectAddPropertyListenerBlock(system, &a, queue) { _, _ in
        guard routeRecovery?.isRecovering != true else { return }
        var shouldRecover = false
        if selector == kAudioHardwarePropertyDevices {
            let topology = outputTopology()
            shouldRecover = topology != lastOutputTopology
            lastOutputTopology = topology
        } else if selector == kAudioHardwarePropertyDefaultOutputDevice || selector == kAudioHardwarePropertyDefaultSystemOutputDevice {
            // Even a coalesced notification with the preferred name already selected can
            // indicate an app stream needs rebinding. Cooldown bounds guard-write echoes.
            shouldRecover = true
        }
        scheduleRestore()
        if shouldRecover && autoRecoveryEnabled {
            routeRecovery?.request(reason: "Audio output changed")
        }
    }
    if status != noErr { fputs("IOGuard: audio listener failed: \(status)\n", stderr) }
}
let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    scheduleRestore()
    if autoRecoveryEnabled { routeRecovery?.request(reason: "Mac woke from sleep") }
}
// AirPlay can reconfigure a display without replacing its audio device object.
let displayObserverStatus = CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
    guard !flags.contains(.beginConfigurationFlag) else { return }
    DispatchQueue.main.async {
        guard routeRecovery?.isRecovering != true else { return }
        scheduleRestore()
        if autoRecoveryEnabled { routeRecovery?.request(reason: "Display configuration changed") }
    }
}, nil)
if displayObserverStatus != .success { fputs("IOGuard: display listener unavailable\n", stderr) }
// A manual, local-only recovery request for the installed background guard.
signal(SIGUSR1, SIG_IGN)
let recoverySignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: queue)
recoverySignal.setEventHandler { routeRecovery?.request(reason: "Manual recovery", automatic: false) }
recoverySignal.resume()
// Give an in-flight handoff a chance to return to the interface on service reload.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
let readyPath = NSHomeDirectory() + "/Library/Application Support/UniversalAudioGuard/ready.pid"
var terminating = false
terminationSignal.setEventHandler {
    guard !terminating else { return }
    terminating = true
    try? FileManager.default.removeItem(atPath: readyPath)
    routeRecovery?.cancel()
    queue.asyncAfter(deadline: .now() + 1.5) { exit(0) }
}
terminationSignal.resume()
// A slow fallback also handles reconnects and wake from sleep.
let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in retryIfIdle() }
enforce()
try? FileManager.default.createDirectory(atPath: (readyPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: readyPath, atomically: true, encoding: .utf8)
RunLoop.main.run()
