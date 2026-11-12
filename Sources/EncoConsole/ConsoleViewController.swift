import AppKit
import Combine

/// A tiny rounded status dot view.
final class DotView: NSView {
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }
    override func draw(_ dirtyBounds: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

/// Main window UI, built with AppKit so the project compiles with Command Line
/// Tools alone (SwiftUI property-wrapper macros require full Xcode).
final class ConsoleViewController: NSViewController {

    private let bt = BluetoothManager()
    private var cancellables = Set<AnyCancellable>()

    // Controls we need to update from state.
    private let statusDot = DotView(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
    private let statusLabel = NSTextField(labelWithString: "Not connected")
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let refreshListButton = NSButton(title: "Refresh list", target: nil, action: nil)
    private let ancSegments = NSSegmentedControl(labels: ["Off", "Noise cancel", "Transparency", "Smart (wind)"],
                                                 trackingMode: .momentary, target: nil, action: nil)
    private let maskLabel = NSTextField(labelWithString: "mask 0x----")
    private let eqSegments = NSSegmentedControl(labels: EQMode.allCases.map { $0.label },
                                                trackingMode: .momentary, target: nil, action: nil)
    private let gameToggle = NSButton(checkboxWithTitle: "Low latency game sound", target: nil, action: nil)
    private let infoTextView = NSTextView()
    private let grantedLabel = NSTextField(labelWithString: "")
    private let cmdField = NSTextField()
    private let payloadField = NSTextField()
    private let jsonField = NSTextField()
    private let logTextView = NSTextView()
    private var devices: [PairedDevice] = []

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 900))

        let content = NSStackView(views: [
            card("Device", "dot.radiowaves.left.and.right", [deviceRow()]),
            card("Noise control  (cmd 0x404)", "waveform", [ancRow(), hintLabel(
                "Off, Noise cancel and Transparency are verified on Enco Air 5 Pro. Smart (wind noise "
                + "reduction) appears as a mode name in the vendor app; its bit is not confirmed on "
                + "every model, so revert if it does nothing.")]),
            card("Equalizer  (cmd 0x406)", "slider.horizontal.3", [eqRow()]),
            card("Game sound  (cmd 0x423)", "gamecontroller", [gameRow()]),
            card("Device info  (JSON diagnostics)", "info.circle", [infoRow()]),
            card("Raw console  (hex)", "terminal", [consoleRow(), jsonRow(), grantedLabel])
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)

        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true

        let logPanel = logRow()

        root.addSubview(scroll)
        root.addSubview(logPanel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            logPanel.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            logPanel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            logPanel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            logPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            logPanel.heightAnchor.constraint(equalToConstant: 210)
        ])

        view = root
        subscribe()
        bt.refreshPairedDevices()
    }

    // MARK: Row builders

    private func card(_ title: String, _ symbol: String, _ rows: [NSView]) -> NSView {
        let header = NSStackView(views: [
            imageView(symbol: symbol),
            NSTextField(labelWithString: title).with { $0.font = .boldSystemFont(ofSize: 13) }
        ])
        header.spacing = 6
        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let box = NSBox()
        box.contentViewMargins = NSSize(width: 10, height: 10)
        box.contentView = stack
        return box
    }

    private func imageView(symbol: String) -> NSView {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        let iv = NSImageView()
        iv.image = img
        return iv
    }

    private func deviceRow() -> NSView {
        statusDot.wantsLayer = true
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        devicePopup.target = self
        devicePopup.action = #selector(deviceChosen)
        connectButton.target = self
        connectButton.action = #selector(connectTapped)
        connectButton.bezelStyle = .rounded
        refreshListButton.target = self
        refreshListButton.action = #selector(refreshListTapped)
        refreshListButton.bezelStyle = .rounded
        let row = NSStackView(views: [statusDot, statusLabel, devicePopup, connectButton, refreshListButton])
        row.spacing = 10
        devicePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return row
    }

    private func ancRow() -> NSView {
        ancSegments.target = self
        ancSegments.action = #selector(ancSegmentTapped)
        ancSegments.segmentStyle = .rounded
        maskLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        maskLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [ancSegments, maskLabel])
        row.spacing = 12
        return row
    }

    private func hintLabel(_ text: String) -> NSView {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 640
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func eqRow() -> NSView {
        eqSegments.target = self
        eqSegments.action = #selector(eqSegmentTapped)
        eqSegments.segmentStyle = .rounded
        eqSegments.setWidth(110, forSegment: 0)
        return eqSegments
    }

    private func gameRow() -> NSView {
        gameToggle.target = self
        gameToggle.action = #selector(gameToggled)
        return gameToggle
    }

    private func infoRow() -> NSView {
        let b1 = NSButton(title: "Read device info", target: self, action: #selector(readInfoTapped))
        let b2 = NSButton(title: "Read RSSI", target: self, action: #selector(readRSSITapped))
        let b3 = NSButton(title: "Read switch inventory (0x503)", target: self, action: #selector(readSwitchesTapped))
        [b1, b2, b3].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
        }
        let buttons = NSStackView(views: [b1, b2, b3])
        buttons.spacing = 8

        infoTextView.isEditable = false
        infoTextView.drawsBackground = false
        infoTextView.textContainerInset = NSSize(width: 2, height: 4)
        infoTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let infoScroll = NSScrollView()
        infoScroll.documentView = infoTextView
        infoScroll.hasVerticalScroller = true
        infoScroll.borderType = .noBorder

        let col = NSStackView(views: [buttons, infoScroll])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        infoScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        infoScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        return col
    }

    private func consoleRow() -> NSView {
        cmdField.placeholderString = "cmd (e.g. 404)"
        cmdField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        payloadField.placeholderString = "payload hex (e.g. 01010800)"
        payloadField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let send = NSButton(title: "Send", target: self, action: #selector(sendRawTapped))
        send.bezelStyle = .rounded
        cmdField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        payloadField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        let row = NSStackView(views: [cmdField, payloadField, send])
        row.spacing = 8
        return row
    }

    private func jsonRow() -> NSView {
        jsonField.placeholderString = #"JSON (e.g. {"cmd":"get_tws_rssi"})"#
        jsonField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let send = NSButton(title: "Send JSON", target: self, action: #selector(sendJSONTapped))
        send.bezelStyle = .rounded
        jsonField.widthAnchor.constraint(greaterThanOrEqualToConstant: 470).isActive = true
        let row = NSStackView(views: [jsonField, send])
        row.spacing = 8
        return row
    }

    private func logRow() -> NSView {
        let header = NSStackView(views: [
            NSTextField(labelWithString: "Log").with { $0.font = .boldSystemFont(ofSize: 12) },
            {
                let b = NSButton(title: "Clear", target: self, action: #selector(clearLogTapped))
                b.bezelStyle = .rounded
                b.controlSize = .small
                return b
            }(),
            NSView() // spring
        ])
        header.spacing = 8

        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.textContainerInset = NSSize(width: 4, height: 4)
        let scroll = NSScrollView()
        scroll.documentView = logTextView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let panel = NSStackView(views: [header, scroll])
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 4
        panel.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        scroll.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalTo: panel.heightAnchor, constant: -30).isActive = true
        return panel
    }

    // MARK: Actions

    @objc private func deviceChosen() {
        let idx = devicePopup.indexOfSelectedItem
        guard idx >= 0 && idx < devices.count else { return }
        bt.selectedAddress = devices[idx].address
    }

    @objc private func connectTapped() {
        if bt.isConnected {
            bt.disconnect()
        } else {
            bt.connect()
        }
    }

    @objc private func refreshListTapped() {
        bt.refreshPairedDevices()
        reloadDevicePopup()
    }

    @objc private func ancSegmentTapped() {
        let masks: [UInt16] = [ANCBit.off, ANCBit.noiseCancel, ANCBit.transparency, ANCBit.smart]
        let idx = ancSegments.selectedSegment
        guard idx >= 0 && idx < masks.count else { return }
        bt.setANC(mask: masks[idx])
    }

    @objc private func eqSegmentTapped() {
        let idx = eqSegments.selectedSegment
        guard idx >= 0, idx < EQMode.allCases.count else { return }
        let mode = EQMode.allCases[idx]
        bt.eqMode = mode.rawValue
        bt.setEQ(mode: mode)
    }

    @objc private func gameToggled() {
        bt.setGame(on: gameToggle.state == .on)
    }

    @objc private func readInfoTapped() { bt.requestDeviceInfo() }
    @objc private func readRSSITapped() { bt.requestRSSI() }
    @objc private func readSwitchesTapped() { bt.refreshSwitchInventory() }

    @objc private func sendRawTapped() {
        let cmd = Int(cmdField.stringValue.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: ""), radix: 16) ?? -1
        guard cmd >= 0 else { return }
        let clean = payloadField.stringValue.trimmingCharacters(in: .whitespaces)
        var payload: [UInt8] = []
        if clean.count % 2 == 0, clean.allSatisfy({ $0.isHexDigit }) {
            var it = clean.makeIterator()
            while let hi = it.next(), let lo = it.next() {
                if let b = UInt8("\(hi)\(lo)", radix: 16) { payload.append(b) }
            }
        }
        bt.send(cmd: cmd, payload: payload)
    }

    @objc private func sendJSONTapped() {
        bt.sendJSON(jsonField.stringValue)
    }

    @objc private func clearLogTapped() { bt.logText = "" }

    // MARK: Wiring + subscriptions

    private func reloadDevicePopup() {
        devices = bt.pairedDevices
        devicePopup.removeAllItems()
        if bt.pairedDevices.isEmpty {
            devicePopup.addItem(withTitle: "No paired devices")
            devicePopup.isEnabled = false
            return
        }
        devicePopup.isEnabled = true
        for dev in bt.pairedDevices {
            devicePopup.addItem(withTitle: "\(dev.name)  (\(dev.address))")
        }
        if let sel = bt.pairedDevices.first(where: { $0.address == bt.selectedAddress }) {
            devicePopup.selectItem(withTitle: "\(sel.name)  (\(sel.address))")
        } else if !bt.selectedAddress.isEmpty {
            devicePopup.selectItem(at: 0)
            bt.selectedAddress = bt.pairedDevices.first?.address ?? ""
        }
    }

    private func subscribe() {
        bt.$pairedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadDevicePopup() }
            .store(in: &cancellables)

        bt.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle: self.statusDot.color = .systemGray; self.statusLabel.stringValue = "Not connected"
                case .connecting: self.statusDot.color = .systemOrange; self.statusLabel.stringValue = "Connecting..."
                case .connected: self.statusDot.color = .systemGreen; self.statusLabel.stringValue = "Connected"
                case .failed(let m): self.statusDot.color = .systemRed; self.statusLabel.stringValue = "Failed: \(m)"
                }
                let connected = state == .connected
                self.connectButton.title = connected ? "Disconnect" : "Connect"
                self.ancSegments.isEnabled = connected
                self.eqSegments.isEnabled = connected
                self.gameToggle.isEnabled = connected
            }
            .store(in: &cancellables)

        bt.$logText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.logTextView.string = text
                let len = self.logTextView.string.count
                if len > 0 {
                    self.logTextView.scrollRangeToVisible(NSRange(location: len - 1, length: 1))
                }
            }
            .store(in: &cancellables)

        bt.$deviceInfo
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                guard !info.isEmpty else {
                    self.infoTextView.string = ""
                    return
                }
                let lines = info.keys.sorted().map { key -> String in
                    let value = info[key] ?? ""
                    return key.padding(toLength: max(key.count, 16), withPad: " ", startingAt: 0) + " " + value
                }
                self.infoTextView.string = lines.joined(separator: "\n")
            }
            .store(in: &cancellables)

        bt.$grantedCommands
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in
                guard let self else { return }
                if granted.isEmpty {
                    self.grantedLabel.stringValue = ""
                } else {
                    self.grantedLabel.stringValue = "Granted commands: " + granted.joined(separator: " ")
                }
            }
            .store(in: &cancellables)

        bt.$ancMask
            .receive(on: RunLoop.main)
            .sink { [weak self] mask in
                guard let self else { return }
                self.maskLabel.stringValue = mask == 0 ? "mask 0x----" : String(format: "mask 0x%04X", mask)
            }
            .store(in: &cancellables)

        bt.$eqMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if let idx = EQMode.allCases.firstIndex(where: { $0.rawValue == mode }) {
                    self.eqSegments.selectedSegment = idx
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Small helpers

private extension NSTextField {
    func with(_ configure: (NSTextField) -> Void) -> NSTextField {
        configure(self)
        return self
    }
}
