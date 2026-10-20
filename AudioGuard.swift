// Universal Audio Guard 1.0.2 — djred
import Foundation
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
func enforce() {
    if timingTest { testEnforcementCount += 1; return }
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
if CommandLine.arguments.contains("--version") { print("Universal Audio Guard 1.0.2"); exit(0) }
if CommandLine.arguments.contains("--list") {
    for d in devices() { print("\(name(d)) | input=\(supports(d, kAudioDevicePropertyScopeInput)) output=\(supports(d, kAudioDevicePropertyScopeOutput))") }
    exit(0)
}
if CommandLine.arguments.contains("--once") { enforce(); exit(0) }
let queue = DispatchQueue.main
var pending: DispatchWorkItem?
func scheduleRestore() {
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
    guard pending == nil else { return }
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
for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDevices] {
    var a = address(selector)
    AudioObjectAddPropertyListenerBlock(system, &a, queue) { _, _ in scheduleRestore() }
}
// A slow fallback also handles reconnects and wake from sleep.
let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in retryIfIdle() }
enforce()
RunLoop.main.run()
