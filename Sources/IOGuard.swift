// IOGuard 1.1.0 — Author: djred
// Native menu bar guard for macOS input, output, and system output devices.

import AppKit
import CoreAudio
import Foundation
import ServiceManagement

private let systemAudioObject = AudioObjectID(kAudioObjectSystemObject)
private let preferredDeviceName = "Universal Audio Thunderbolt"
private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"

private let inputUIDKey = "IOGuard.preferredInputUID"
private let outputUIDKey = "IOGuard.preferredOutputUID"
private let enabledKey = "IOGuard.enabled"
private let legacyGuardPath = NSHomeDirectory() + "/Library/LaunchAgents/com.djred.universalaudioguard.plist"

private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

private struct DeviceRead {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}

private struct DeviceListRead {
    let devices: [DeviceRead]
    let error: String?
}

private func readDeviceName(_ device: AudioDeviceID) -> (String?, OSStatus) {
    var address = propertyAddress(kAudioObjectPropertyName)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.stride)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
    }
    guard status == noErr else { return (nil, status) }
    return (value as String, noErr)
}

private func readDeviceUID(_ device: AudioDeviceID) -> (String?, OSStatus) {
    var address = propertyAddress(kAudioDevicePropertyDeviceUID)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.stride)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
    }
    guard status == noErr else { return (nil, status) }
    return (value as String, noErr)
}

private func deviceSupports(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = propertyAddress(kAudioDevicePropertyStreams, scope: scope)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
}

private func readDevices() -> DeviceListRead {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(systemAudioObject, &address, 0, nil, &size)
    guard status == noErr else {
        return DeviceListRead(devices: [], error: "Unable to read audio devices: Core Audio error \(status).")
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return DeviceListRead(devices: [], error: nil) }

    var identifiers = [AudioDeviceID](repeating: 0, count: count)
    status = identifiers.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
        return AudioObjectGetPropertyData(systemAudioObject, &address, 0, nil, &size, baseAddress)
    }
    guard status == noErr else {
        return DeviceListRead(devices: [], error: "Unable to read audio devices: Core Audio error \(status).")
    }

    var propertyErrors: [String] = []
    let devices = identifiers.compactMap { identifier -> DeviceRead? in
        let (name, nameStatus) = readDeviceName(identifier)
        let (uid, uidStatus) = readDeviceUID(identifier)
        guard uidStatus == noErr, let uid, !uid.isEmpty else {
            propertyErrors.append("Skipped device ID \(identifier): unable to read its UID (\(statusDescription(uidStatus))).")
            return nil
        }
        if nameStatus != noErr {
            propertyErrors.append("Unable to read the name for device ID \(identifier) (\(statusDescription(nameStatus))).")
        }
        let safeName = nameStatus == noErr ? (name ?? "Unknown audio device") : "Unknown audio device"
        return DeviceRead(
            id: identifier,
            uid: uid,
            name: safeName,
            hasInput: deviceSupports(identifier, scope: kAudioDevicePropertyScopeInput),
            hasOutput: deviceSupports(identifier, scope: kAudioDevicePropertyScopeOutput)
        )
    }
    return DeviceListRead(devices: devices, error: propertyErrors.isEmpty ? nil : propertyErrors.joined(separator: "\n"))
}

private func readSystemDevice(_ selector: AudioObjectPropertySelector) -> (AudioDeviceID?, OSStatus) {
    var address = propertyAddress(selector)
    var device: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(systemAudioObject, &address, 0, nil, &size, &device)
    return status == noErr ? (device, noErr) : (nil, status)
}

private func deviceName(_ identifier: AudioDeviceID, in devices: [DeviceRead]) -> String {
    if let device = devices.first(where: { $0.id == identifier }) { return device.name }
    let (name, status) = readDeviceName(identifier)
    if status == noErr, let name { return name }
    return "Unknown device (ID \(identifier))"
}

private func statusDescription(_ status: OSStatus) -> String {
    "Core Audio error \(status)"
}

private func printDiagnostics() {
    let result = readDevices()
    if let error = result.error { print(error) }
    if result.devices.isEmpty {
        print("No audio devices with readable UIDs were found.")
    }
    for device in result.devices {
        print("\(device.name) | UID=\(device.uid) | input=\(device.hasInput) output=\(device.hasOutput)")
    }

    let defaults: [(String, AudioObjectPropertySelector)] = [
        ("Input", kAudioHardwarePropertyDefaultInputDevice),
        ("Output", kAudioHardwarePropertyDefaultOutputDevice),
        ("System output", kAudioHardwarePropertyDefaultSystemOutputDevice)
    ]
    for (label, selector) in defaults {
        let (identifier, status) = readSystemDevice(selector)
        if status == noErr, let identifier {
            print("Current \(label.lowercased()): \(deviceName(identifier, in: result.devices))")
        } else {
            print("Current \(label.lowercased()): unavailable (\(statusDescription(status)))")
        }
    }
}

private final class IOGuardAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard

    private var audioDevices: [DeviceRead] = []
    private var deviceReadError: String?
    private var listenerErrors: [String] = []
    private var lastInputState = "Reading input state…"
    private var lastOutputState = "Reading output state…"
    private var lastSystemOutputState = "Reading system output state…"
    private var lastLoginError: String?

    private var preferredInputUID = ""
    private var preferredOutputUID = ""
    private var isEnabled = true
    private var showPreferencesOnFirstRun = false
    private var listenersInstalled = false
    private var pendingEnforcement: DispatchWorkItem?
    private var fallbackTimer: Timer?

    private var legacyGuardInstalled: Bool {
        FileManager.default.fileExists(atPath: legacyGuardPath)
    }

    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var inputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var outputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var enabledCheckbox = NSButton(checkboxWithTitle: "Enable audio guard", target: nil, action: nil)
    private var loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private var inputStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var outputStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var systemOutputStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var overallStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var loginStatusLabel = NSTextField(wrappingLabelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadPreferences()
        refreshDevices()
        createStatusItem()
        createPreferencesWindow()
        installAudioListeners()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshDevices()
            // A fallback tick must not cut short the one-second Core Audio debounce.
            if self.pendingEnforcement == nil {
                self.enforceIfEnabled()
            }
        }
        enforceIfEnabled()
        updateInterface()
        if showPreferencesOnFirstRun {
            showPreferencesOnFirstRun = false
            showPreferences(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingEnforcement?.cancel()
        fallbackTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPreferences(nil) }
        return true
    }

    private func loadPreferences() {
        showPreferencesOnFirstRun = defaults.object(forKey: inputUIDKey) == nil
            && defaults.object(forKey: outputUIDKey) == nil
            && defaults.object(forKey: enabledKey) == nil
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(!legacyGuardInstalled, forKey: enabledKey)
        }
        isEnabled = defaults.bool(forKey: enabledKey)
        preferredInputUID = defaults.string(forKey: inputUIDKey) ?? ""
        preferredOutputUID = defaults.string(forKey: outputUIDKey) ?? ""
    }

    private func initializePreferredDevicesIfNeeded() {
        if preferredInputUID.isEmpty {
            if let choice = initialDevice(forInput: true) {
                preferredInputUID = choice.uid
                defaults.set(choice.uid, forKey: inputUIDKey)
            }
        }
        if preferredOutputUID.isEmpty {
            if let choice = initialDevice(forInput: false) {
                preferredOutputUID = choice.uid
                defaults.set(choice.uid, forKey: outputUIDKey)
            }
        }
    }

    private func initialDevice(forInput: Bool) -> DeviceRead? {
        let canUse: (DeviceRead) -> Bool = { forInput ? $0.hasInput : $0.hasOutput }
        let namedMatches = audioDevices.filter {
            canUse($0) && $0.name.caseInsensitiveCompare(preferredDeviceName) == .orderedSame
        }
        if namedMatches.count == 1 { return namedMatches[0] }

        let selector = forInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let (current, status) = readSystemDevice(selector)
        if status == noErr, let current, let selected = audioDevices.first(where: { $0.id == current && canUse($0) }) {
            return selected
        }
        return nil
    }

    private func refreshDevices() {
        let result = readDevices()
        audioDevices = result.devices
        deviceReadError = result.error
        initializePreferredDevicesIfNeeded()
        populate(inputPopup, forInput: true, preferredUID: preferredInputUID)
        populate(outputPopup, forInput: false, preferredUID: preferredOutputUID)
        updateStatusLabels()
    }

    private func populate(_ popup: NSPopUpButton, forInput: Bool, preferredUID: String) {
        popup.removeAllItems()
        let supported = audioDevices.filter { forInput ? $0.hasInput : $0.hasOutput }
        let frequencies = Dictionary(grouping: supported, by: { $0.name }).mapValues(\.count)

        if !preferredUID.isEmpty, !supported.contains(where: { $0.uid == preferredUID }) {
            popup.addItem(withTitle: "Missing device — \(shortUID(preferredUID))")
            popup.lastItem?.representedObject = preferredUID
        }

        for device in supported.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let title = frequencies[device.name, default: 0] > 1
                ? "\(device.name) — \(shortUID(device.uid))"
                : device.name
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = device.uid
        }

        if supported.isEmpty && preferredUID.isEmpty {
            popup.addItem(withTitle: forInput ? "No input devices found" : "No output devices found")
            popup.lastItem?.isEnabled = false
        } else if preferredUID.isEmpty {
            popup.insertItem(withTitle: forInput ? "Choose input device…" : "Choose output device…", at: 0)
            popup.item(at: 0)?.isEnabled = false
        }
        if !preferredUID.isEmpty {
            if let selectedIndex = popup.itemArray.firstIndex(where: { $0.representedObject as? String == preferredUID }) {
                popup.selectItem(at: selectedIndex)
            }
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func shortUID(_ uid: String) -> String {
        uid.count > 28 ? "…\(uid.suffix(24))" : uid
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let artwork = NSImage(named: NSImage.Name("MenuBarIconTemplate"))
                ?? NSImage(systemSymbolName: "lock.speaker", accessibilityDescription: "IOGuard")
                ?? NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "IOGuard")
            artwork?.size = NSSize(width: 18, height: 18)
            artwork?.isTemplate = true
            button.image = artwork
            button.title = artwork == nil ? "IOG" : ""
            button.toolTip = "IOGuard — input and output device guard"
            button.setAccessibilityLabel("IOGuard")
        }
        statusItem = item
        rebuildStatusMenu()
    }

    private func createPreferencesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "IOGuard Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let title = NSTextField(labelWithString: "IOGuard")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let version = NSTextField(labelWithString: "Version \(appVersion)")
        version.textColor = .secondaryLabelColor
        version.font = .systemFont(ofSize: 12)
        let appIconView = NSImageView(frame: NSRect(x: 0, y: 0, width: 38, height: 38))
        appIconView.image = NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.setContentHuggingPriority(.required, for: .horizontal)
        appIconView.setContentHuggingPriority(.required, for: .vertical)
        appIconView.widthAnchor.constraint(equalToConstant: 38).isActive = true
        appIconView.heightAnchor.constraint(equalToConstant: 38).isActive = true

        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(enabledChanged(_:))
        inputPopup.target = self
        inputPopup.action = #selector(preferredDeviceChanged(_:))
        outputPopup.target = self
        outputPopup.action = #selector(preferredDeviceChanged(_:))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged(_:))

        inputStatusLabel = NSTextField(wrappingLabelWithString: "")
        outputStatusLabel = NSTextField(wrappingLabelWithString: "")
        systemOutputStatusLabel = NSTextField(wrappingLabelWithString: "")
        overallStatusLabel = NSTextField(wrappingLabelWithString: "")
        loginStatusLabel = NSTextField(wrappingLabelWithString: "")
        overallStatusLabel.textColor = .secondaryLabelColor
        loginStatusLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [appIconView, title, version])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let inputRow = selectorRow(label: "Preferred input", control: inputPopup)
        let outputRow = selectorRow(label: "Preferred output", control: outputPopup)

        let refreshButton = NSButton(title: "Refresh Devices", target: self, action: #selector(refreshButtonPressed(_:)))
        let refreshRow = NSStackView(views: [refreshButton, NSView()])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 8

        let loginStack = NSStackView(views: [loginCheckbox, loginStatusLabel])
        loginStack.orientation = .vertical
        loginStack.alignment = .leading
        loginStack.spacing = 4

        let statusStack = NSStackView(views: [inputStatusLabel, outputStatusLabel, systemOutputStatusLabel, overallStatusLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 5

        let stack = NSStackView(views: [header, enabledCheckbox, separator(), inputRow, outputRow, refreshRow, separator(), loginStack, separator(), statusStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
            ])
        }
        inputPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        outputPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        inputStatusLabel.widthAnchor.constraint(equalToConstant: 510).isActive = true
        outputStatusLabel.widthAnchor.constraint(equalToConstant: 510).isActive = true
        systemOutputStatusLabel.widthAnchor.constraint(equalToConstant: 510).isActive = true
        overallStatusLabel.widthAnchor.constraint(equalToConstant: 510).isActive = true
        loginStatusLabel.widthAnchor.constraint(equalToConstant: 510).isActive = true

        window.center()
        preferencesWindow = window
        updateInterface()
    }

    private func selectorRow(label: String, control: NSView) -> NSStackView {
        let name = NSTextField(labelWithString: label)
        name.widthAnchor.constraint(equalToConstant: 128).isActive = true
        let row = NSStackView(views: [name, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func installAudioListeners() {
        guard !listenersInstalled else { return }
        listenersInstalled = true

        let registrations: [(AudioObjectPropertySelector, Bool)] = [
            (kAudioHardwarePropertyDevices, true),
            (kAudioHardwarePropertyDefaultInputDevice, false),
            (kAudioHardwarePropertyDefaultOutputDevice, false),
            (kAudioHardwarePropertyDefaultSystemOutputDevice, false)
        ]
        for (selector, isTopologyChange) in registrations {
            var address = propertyAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(systemAudioObject, &address, DispatchQueue.main) { [weak self] _, _ in
                guard let self else { return }
                if isTopologyChange {
                    self.refreshDevices()
                } else {
                    self.updateStatusLabels()
                }
                self.scheduleEnforcement()
            }
            if status != noErr {
                listenerErrors.append("Unable to monitor Core Audio property \(selector): \(statusDescription(status)).")
            }
        }
    }

    private func scheduleEnforcement() {
        guard isEnabled else { return }
        pendingEnforcement?.cancel()
        lastInputState = "Input: Waiting to restore preferred device."
        lastOutputState = "Output: Waiting to restore preferred device."
        lastSystemOutputState = "System output: Waiting to restore preferred device."
        updateStatusLabels()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEnforcement = nil
            self.refreshDevices()
            self.enforceIfEnabled()
        }
        pendingEnforcement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func enforceIfEnabled() {
        if legacyGuardInstalled {
            lastInputState = "Input: Paused — original guard is installed."
            lastOutputState = "Output: Paused — original guard is installed."
            lastSystemOutputState = "System output: Paused — original guard is installed."
            updateStatusLabels()
            return
        }
        guard isEnabled else {
            updateStatusLabels()
            return
        }
        lastInputState = enforce(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            preferredUID: preferredInputUID,
            isInput: true,
            label: "Input"
        )
        lastOutputState = enforce(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            preferredUID: preferredOutputUID,
            isInput: false,
            label: "Output"
        )
        lastSystemOutputState = enforce(
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            preferredUID: preferredOutputUID,
            isInput: false,
            label: "System output"
        )
        updateStatusLabels()
    }

    private func enforce(
        selector: AudioObjectPropertySelector,
        preferredUID: String,
        isInput: Bool,
        label: String
    ) -> String {
        guard !preferredUID.isEmpty else {
            return "\(label): Choose a preferred device in Preferences."
        }
        guard let preferred = audioDevices.first(where: { $0.uid == preferredUID }) else {
            return "\(label): Preferred device not found (\(shortUID(preferredUID)))."
        }
        guard isInput ? preferred.hasInput : preferred.hasOutput else {
            return "\(label): \(preferred.name) does not support this audio direction."
        }

        let (current, readStatus) = readSystemDevice(selector)
        guard readStatus == noErr, let current else {
            return "\(label): Unable to read current device (\(statusDescription(readStatus)))."
        }
        if current == preferred.id {
            return "\(label): Active — \(preferred.name)."
        }

        var address = propertyAddress(selector)
        var desired = preferred.id
        let writeStatus = AudioObjectSetPropertyData(
            systemAudioObject,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &desired
        )

        // Always read the value back, including after a failed write, to report the actual state.
        let (verified, verifyStatus) = readSystemDevice(selector)
        if verifyStatus != noErr {
            return "\(label): Unable to verify device after change (\(statusDescription(verifyStatus)))."
        }
        guard let verified else {
            return "\(label): Device verification returned no current device."
        }
        if writeStatus != noErr {
            return "\(label): Restore failed (\(statusDescription(writeStatus)))."
        }
        guard verified == preferred.id else {
            return "\(label): Restore did not take effect."
        }
        return "\(label): Restored — \(preferred.name)."
    }

    private func currentDeviceSummary(_ selector: AudioObjectPropertySelector) -> String {
        let (identifier, status) = readSystemDevice(selector)
        guard status == noErr, let identifier else { return "Unavailable (\(statusDescription(status)))" }
        return deviceName(identifier, in: audioDevices)
    }

    private func updateStatusLabels() {
        enabledCheckbox.isEnabled = !legacyGuardInstalled
        inputStatusLabel.stringValue = displayStatus(
            lastInputState,
            label: "Input",
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        outputStatusLabel.stringValue = displayStatus(
            lastOutputState,
            label: "Output",
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        systemOutputStatusLabel.stringValue = displayStatus(
            lastSystemOutputState,
            label: "System output",
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice
        )

        var details: [String] = []
        if !isEnabled { details.append("Guard is paused.") }
        if legacyGuardInstalled {
            details.append("Original guard is installed. Run its Uninstall.command before enabling IOGuard.")
        }
        if let deviceReadError { details.append(deviceReadError) }
        details.append(contentsOf: listenerErrors)
        if let lastLoginError { details.append(lastLoginError) }
        overallStatusLabel.stringValue = details.isEmpty ? "Device status is monitored continuously." : details.joined(separator: "\n")
        updateLoginStatus()
        rebuildStatusMenu()
    }

    private func displayStatus(
        _ state: String,
        label: String,
        selector: AudioObjectPropertySelector
    ) -> String {
        let (currentID, currentStatus) = readSystemDevice(selector)
        let current = currentStatus == noErr && currentID != nil
            ? deviceName(currentID!, in: audioDevices)
            : "Unavailable (\(statusDescription(currentStatus)))"
        if legacyGuardInstalled || !isEnabled {
            return "\(label): Paused · Current: \(current)"
        }
        let preferredUID = selector == kAudioHardwarePropertyDefaultInputDevice ? preferredInputUID : preferredOutputUID
        let expectedDevice = audioDevices.first(where: { $0.uid == preferredUID })
        if currentStatus == noErr, let currentID, let expectedDevice, currentID == expectedDevice.id {
            if state.contains(": Restored —") { return state }
            return "\(label): Active — \(expectedDevice.name)."
        }
        if currentStatus != noErr && state.contains("Unable to read current device") { return state }
        return "\(state) · Current: \(current)"
    }

    private func updateInterface() {
        enabledCheckbox.state = isEnabled ? .on : .off
        enabledCheckbox.isEnabled = !legacyGuardInstalled
        updateLoginStatus()
        updateStatusLabels()
    }

    private func updateLoginStatus() {
        guard loginCheckbox.window != nil else { return }
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            loginCheckbox.state = service.status == .enabled ? .on : .off
            switch service.status {
            case .enabled:
                loginStatusLabel.stringValue = "IOGuard is registered to launch when you sign in."
            case .requiresApproval:
                loginStatusLabel.stringValue = "Approve IOGuard in System Settings → General → Login Items."
            case .notRegistered:
                loginStatusLabel.stringValue = "IOGuard will not launch automatically."
            case .notFound:
                loginStatusLabel.stringValue = "Launch at login is available after IOGuard is installed as an app."
            @unknown default:
                loginStatusLabel.stringValue = "Launch at login status is unavailable."
            }
        } else {
            loginCheckbox.state = .off
            loginCheckbox.isEnabled = false
            loginStatusLabel.stringValue = "Launch at login requires macOS 13 or later."
        }
        if let lastLoginError { loginStatusLabel.stringValue += "\n\(lastLoginError)" }
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let stateTitle = legacyGuardInstalled
            ? "Original audio guard is installed"
            : (isEnabled ? "IOGuard is enabled" : "IOGuard is paused")
        let state = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let toggle = NSMenuItem(title: isEnabled ? "Pause Guard" : "Enable Guard", action: #selector(toggleGuard(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = !legacyGuardInstalled
        menu.addItem(toggle)

        let about = NSMenuItem(title: "About IOGuard", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit IOGuard", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func showPreferences(_ sender: Any?) {
        guard let preferencesWindow else { return }
        updateInterface()
        preferencesWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleGuard(_ sender: Any?) {
        guard !legacyGuardInstalled else {
            updateStatusLabels()
            return
        }
        isEnabled.toggle()
        defaults.set(isEnabled, forKey: enabledKey)
        if isEnabled {
            enforceIfEnabled()
        } else {
            pendingEnforcement?.cancel()
            pendingEnforcement = nil
            updateStatusLabels()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "IOGuard \(appVersion)"
        alert.informativeText = "Keeps your preferred input, output, and system output devices selected.\n\nAuthor: djred"
        alert.alertStyle = .informational
        alert.icon = NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        guard !legacyGuardInstalled else {
            sender.state = isEnabled ? .on : .off
            updateStatusLabels()
            return
        }
        isEnabled = sender.state == .on
        defaults.set(isEnabled, forKey: enabledKey)
        if isEnabled {
            enforceIfEnabled()
        } else {
            pendingEnforcement?.cancel()
            pendingEnforcement = nil
            updateStatusLabels()
        }
    }

    @objc private func preferredDeviceChanged(_ sender: NSPopUpButton) {
        guard let uid = sender.selectedItem?.representedObject as? String else { return }
        if sender === inputPopup {
            preferredInputUID = uid
            defaults.set(uid, forKey: inputUIDKey)
        } else if sender === outputPopup {
            preferredOutputUID = uid
            defaults.set(uid, forKey: outputUIDKey)
        } else {
            return
        }
        lastInputState = "Input preference saved."
        lastOutputState = "Output preference saved."
        lastSystemOutputState = "System output follows the preferred output device."
        updateStatusLabels()
        scheduleEnforcement()
    }

    @objc private func refreshButtonPressed(_ sender: NSButton) {
        refreshDevices()
        if pendingEnforcement == nil { enforceIfEnabled() }
    }

    @objc private func loginChanged(_ sender: NSButton) {
        lastLoginError = nil
        guard #available(macOS 13.0, *) else {
            lastLoginError = "Launch at login requires macOS 13 or later."
            updateStatusLabels()
            return
        }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastLoginError = "Unable to update launch at login: \(error.localizedDescription)"
        }
        updateStatusLabels()
    }

    func windowWillClose(_ notification: Notification) {
        // Preferences remain available from the menu bar after the window is closed.
    }
}

if CommandLine.arguments.contains("--diagnose") {
    printDiagnostics()
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
private let appDelegate = IOGuardAppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
