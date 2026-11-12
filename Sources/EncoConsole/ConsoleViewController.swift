import AppKit
import Combine

// MARK: - Design tokens (dark theme)

private enum Theme {
    static let windowBg = NSColor(srgbRed: 0x1a / 255.0, green: 0x1b / 255.0, blue: 0x1e / 255.0, alpha: 1)
    static let sidebarBg = NSColor(srgbRed: 0x17 / 255.0, green: 0x17 / 255.0, blue: 0x19 / 255.0, alpha: 1)
    static let cardBg = NSColor(srgbRed: 0x25 / 255.0, green: 0x26 / 255.0, blue: 0x2a / 255.0, alpha: 1)
    static let terminalBg = NSColor(srgbRed: 0x12 / 255.0, green: 0x13 / 255.0, blue: 0x16 / 255.0, alpha: 1)
    static let border = NSColor.white.withAlphaComponent(0.08)
    static let accent = NSColor.systemBlue
    static let green = NSColor.systemGreen
    static let orange = NSColor.systemOrange
    static func white(_ a: CGFloat) -> NSColor { .white.withAlphaComponent(a) }
}

private func tintedDot(_ color: NSColor) -> NSImageView {
    let iv = NSImageView()
    iv.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
    iv.contentTintColor = color
    return iv
}

final class ConsoleViewController: NSViewController {

    private let bt = BluetoothManager()
    private var cancellables = Set<AnyCancellable>()

    // Sidebar
    private var deviceRowsStack: NSStackView!
    private var deviceNameLabel = NSTextField(labelWithString: "Not connected")
    private var deviceAddrLabel = NSTextField(labelWithString: "pick a device below")
    private var deviceStatusLabel = NSTextField(labelWithString: "OFFLINE")
    private var sidebarConnectButton: NSButton!

    // Banner
    private var latencyPill = NSTextField(labelWithString: "standard latency")

    // Noise control
    private var ancPillButtons: [NSButton] = []
    private var ancMaskLabel = NSTextField(labelWithString: "mask 0x----")
    private var depthValueLabel: NSTextField?

    // EQ
    private var eqPillButtons: [NSButton] = []

    // Game
    private var gameSwitch = NSSwitch()
    private var gameStatusLabel = NSTextField(labelWithString: "standard buffer")
    private var gameOn = false

    // Diagnostics
    private var terminalView = NSTextView()
    private var grantedLabel = NSTextField(labelWithString: "")
    private var renderedLogCount = 0
    private var cmdField = NSTextField()
    private var payloadField = NSTextField()
    private var jsonField = NSTextField()

    // Status bar
    private var statusDot: NSImageView = tintedDot(.systemGray)
    private var statusLabel = NSTextField(labelWithString: "Not connected")

    // MARK: - Layout

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1060, height: 800))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.windowBg.cgColor

        // Header (traffic lights occupy the leading ~76pt of a full-size-content window)
        let header = NSStackView(views: [
            spacer(64),
            imageView("dot.radiowaves.left.and.right", tint: Theme.accent, size: 14),
            NSTextField(labelWithString: "Enco Console").with {
                $0.font = .systemFont(ofSize: 13, weight: .semibold)
                $0.textColor = Theme.white(0.9)
            },
            versionChip()
        ])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 14)

        // Sidebar
        let pairedCaption = NSTextField(labelWithString: "PAIRED DEVICES").with {
            $0.font = .systemFont(ofSize: 10, weight: .bold)
            $0.textColor = Theme.white(0.4)
        }
        deviceRowsStack = NSStackView(views: [])
        deviceRowsStack.orientation = .vertical
        deviceRowsStack.alignment = .leading
        deviceRowsStack.spacing = 4

        let sidebarContent = NSStackView(views: [
            sidebarDeviceCard(), pairedCaption, deviceRowsStack, NSView()
        ])
        sidebarContent.orientation = .vertical
        sidebarContent.alignment = .leading
        sidebarContent.spacing = 10
        sidebarContent.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        sidebarContent.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = Theme.sidebarBg.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarContent)
        NSLayoutConstraint.activate([
            sidebarContent.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarContent.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarContent.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarContent.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        // Main scroll area
        let mainStack = NSStackView(views: [
            banner(), noiseCard(), eqCard(), gameCard(), diagnosticsCard()
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let mainScroll = NSScrollView()
        mainScroll.documentView = mainStack
        mainScroll.hasVerticalScroller = true
        mainScroll.autohidesScrollers = true
        mainScroll.drawsBackground = false
        mainScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: mainScroll.contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: mainScroll.contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: mainScroll.contentView.trailingAnchor)
        ])

        // Status bar
        let statusbar = NSStackView(views: [
            statusDot,
            statusLabel,
            NSTextField(labelWithString: "\u{2022}").with { $0.textColor = Theme.white(0.3) },
            NSTextField(labelWithString: "OPPO vendor protocol over RFCOMM SPP").with {
                $0.textColor = Theme.white(0.35); $0.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            },
            NSView(),
            NSTextField(labelWithString: "unofficial community tool").with {
                $0.textColor = Theme.white(0.3); $0.font = .systemFont(ofSize: 10)
            }
        ])
        statusbar.orientation = .horizontal
        statusbar.spacing = 6
        statusbar.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

        // Assemble
        root.addSubview(header)
        root.addSubview(sidebar)
        root.addSubview(mainScroll)
        root.addSubview(statusbar)
        header.translatesAutoresizingMaskIntoConstraints = false
        statusbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            sidebar.topAnchor.constraint(equalTo: header.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: statusbar.topAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 280),

            mainScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            mainScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mainScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainScroll.bottomAnchor.constraint(equalTo: statusbar.topAnchor),

            statusbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusbar.heightAnchor.constraint(equalToConstant: 24),

            mainStack.widthAnchor.constraint(equalTo: mainScroll.contentView.widthAnchor, constant: -36)
        ])
        for arranged in mainStack.arrangedSubviews {
            arranged.widthAnchor.constraint(equalTo: mainScroll.contentView.widthAnchor, constant: -36).isActive = true
        }

        view = root
        subscribe()
        bt.refreshPairedDevices()
        bt.announceReady()

    }

    // MARK: - Sidebar

    private func sidebarDeviceCard() -> NSView {
        let statusLine = NSStackView(views: [miniDot(Theme.orange), deviceStatusLabel.with {
            $0.font = .systemFont(ofSize: 10, weight: .bold)
            $0.textColor = Theme.orange
        }])
        statusLine.spacing = 5

        deviceNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        deviceNameLabel.textColor = Theme.white(0.92)
        deviceAddrLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        deviceAddrLabel.textColor = Theme.white(0.45)

        let codecChip = NSTextField(labelWithString: "SPP").with {
            $0.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
            $0.textColor = Theme.white(0.7)
            $0.alignment = .center
            $0.wantsLayer = true
            $0.layer?.backgroundColor = Theme.white(0.1).cgColor
            $0.layer?.cornerRadius = 4
        }

        let head = NSStackView(views: [
            NSStackView(views: [statusLine, deviceNameLabel, deviceAddrLabel]).with {
                $0.orientation = .vertical; $0.alignment = .leading; $0.spacing = 2
            },
            codecChip
        ])
        head.spacing = 6

        // Battery: this firmware does not expose a battery read over the protocol yet,
        // so the tiles show placeholders instead of invented numbers.
        let batteryGrid = NSStackView(views: [batteryTile("L"), batteryTile("R"), batteryTile("Case")])
        batteryGrid.distribution = .fillEqually
        batteryGrid.spacing = 4
        batteryGrid.widthAnchor.constraint(equalToConstant: 224).isActive = true

        sidebarConnectButton = NSButton(title: "Connect", target: self, action: #selector(mainConnectTapped))
        sidebarConnectButton.bezelStyle = .rounded
        sidebarConnectButton.controlSize = .small

        let body = NSStackView(views: [head, batteryGrid, sidebarConnectButton])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.white(0.06).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.border.cgColor
        container.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: 12)
        ])
        container.widthAnchor.constraint(equalToConstant: 256).isActive = true
        return container
    }

    private func batteryTile(_ label: String) -> NSView {
        let value = NSTextField(labelWithString: "--").with {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            $0.textColor = Theme.white(0.55)
            $0.alignment = .center
        }
        let caption = NSTextField(labelWithString: label).with {
            $0.font = .systemFont(ofSize: 9, weight: .bold)
            $0.textColor = Theme.white(0.4)
            $0.alignment = .center
        }
        let col = NSStackView(views: [value, caption])
        col.orientation = .vertical
        col.spacing = 1
        col.wantsLayer = true
        col.layer?.backgroundColor = Theme.white(0.03).cgColor
        col.layer?.cornerRadius = 7
        col.layer?.borderWidth = 1
        col.layer?.borderColor = Theme.border.cgColor
        return col
    }

    private func pairedRow(_ dev: PairedDevice) -> NSView {
        // Plain NSButton row: no custom view subclass in the click path.
        let row = NSButton(title: dev.name, target: self, action: #selector(pairedRowTapped(_:)))
        row.isBordered = false
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.identifier = NSUserInterfaceItemIdentifier(dev.address)
        row.toolTip = dev.address
        row.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        row.imagePosition = .imageLeading
        row.alignment = .left
        row.font = .systemFont(ofSize: 12, weight: .medium)
        row.contentTintColor = Theme.white(0.8)
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        row.widthAnchor.constraint(equalToConstant: 256).isActive = true
        row.setButtonType(.momentaryPushIn)
        refreshRowSelection(row: row, address: dev.address)
        return row
    }

    private func refreshSidebarSelection() {
        let rows = deviceRowsStack.arrangedSubviews.compactMap { $0 as? NSButton }
        for (i, row) in rows.enumerated() where i < bt.pairedDevices.count {
            refreshRowSelection(row: row, address: bt.pairedDevices[i].address)
        }
        if let sel = bt.pairedDevices.first(where: { $0.address == bt.selectedAddress }) {
            deviceNameLabel.stringValue = sel.name
            deviceAddrLabel.stringValue = sel.address
        }
    }

    private func refreshRowSelection(row: NSView, address: String) {
        let selected = address == bt.selectedAddress
        row.layer?.backgroundColor = selected ? Theme.white(0.08).cgColor : Theme.white(0.02).cgColor
        row.layer?.borderWidth = selected ? 1 : 0
        row.layer?.borderColor = Theme.accent.withAlphaComponent(0.5).cgColor
        (row as? NSButton)?.attributedTitle = NSAttributedString(
            string: (row as? NSButton)?.title ?? "",
            attributes: [
                .foregroundColor: selected ? NSColor.white : Theme.white(0.8),
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium)
            ])
    }

    // MARK: - Banner

    private func banner() -> NSView {
        let chip = imageView("hifispeaker.2", tint: Theme.accent, size: 18).with {
            $0.wantsLayer = true
            $0.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
            $0.layer?.cornerRadius = 10
        }
        chip.widthAnchor.constraint(equalToConstant: 40).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let title = NSTextField(labelWithString: "Audio Settings & Parameters").with {
            $0.font = .systemFont(ofSize: 15, weight: .semibold)
            $0.textColor = Theme.white(0.92)
        }
        let subtitle = NSTextField(labelWithString:
            "Vendor-protocol control for your Enco earbuds. Verified knobs are live; unverified ones are labelled.").with {
            $0.font = .systemFont(ofSize: 11)
            $0.textColor = Theme.white(0.45)
        }
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        latencyPill.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        latencyPill.textColor = Theme.white(0.5)
        latencyPill.wantsLayer = true
        latencyPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        latencyPill.layer?.cornerRadius = 9
        latencyPill.layer?.borderWidth = 1
        latencyPill.layer?.borderColor = Theme.border.cgColor

        let row = NSStackView(views: [chip, text, NSView(), latencyPill])
        row.spacing = 10
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.border.cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let wrap = NSStackView(views: [row, divider])
        wrap.orientation = .vertical
        wrap.spacing = 12
        return wrap
    }

    // MARK: - Cards

    private func noiseCard() -> NSView {
        let pills = ["Off", "Noise cancel", "Transparency", "Smart (wind)"]
        let row = NSStackView(views: [])
        row.spacing = 2
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        row.layer?.cornerRadius = 9
        row.layer?.borderWidth = 1
        row.layer?.borderColor = Theme.border.cgColor
        row.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (i, label) in pills.enumerated() {
            let b = pillButton(label, index: i, action: #selector(ancPillTapped(_:)))
            ancPillButtons.append(b)
            row.addArrangedSubview(b)
        }
        applyPillSelection(ancPillButtons, selected: 1)

        ancMaskLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        ancMaskLabel.textColor = Theme.white(0.4)

        let slider = NSSlider(value: 1, minValue: 1, maxValue: 3, target: self, action: #selector(depthSliderChanged(_:)))
        slider.numberOfTickMarks = 3
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let depthValue = NSTextField(labelWithString: "mild").with {
            $0.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            $0.textColor = Theme.accent
            $0.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        depthValueLabel = depthValue
        let depthRow = NSStackView(views: [
            NSStackView(views: [
                NSTextField(labelWithString: "Cancellation depth").with {
                    $0.font = .systemFont(ofSize: 12, weight: .medium); $0.textColor = Theme.white(0.75)
                },
                NSTextField(labelWithString: "level form (type 2) - unverified on this model").with {
                    $0.font = .systemFont(ofSize: 10); $0.textColor = Theme.white(0.35)
                }
            ]).with { $0.orientation = .vertical; $0.alignment = .leading; $0.spacing = 1 },
            NSView(),
            slider,
            depthValue
        ])
        depthRow.spacing = 8

        let head = cardHeader(icon: "waveform", tint: .systemPurple, title: "NOISE CONTROL",
                              note: "cmd 0x404", trailing: ancMaskLabel)
        let body = NSStackView(views: [head, row, depthRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        return wrapCard(body)
    }

    @objc private func ancPillTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let i = Int(raw) else { return }
        let masks: [UInt16] = [ANCBit.off, ANCBit.noiseCancel, ANCBit.transparency, ANCBit.smart]
        applyPillSelection(ancPillButtons, selected: i)
        bt.setANC(mask: masks[i])
    }

    @objc private func depthSliderChanged(_ sender: NSSlider) {
        let v = sender.integerValue
        depthValueLabel?.stringValue = ["mild", "medium", "deep"][min(max(v - 1, 0), 2)]
        bt.send(cmd: Cmd.ancSet, payload: [0x02, UInt8(v)])
    }

    private func eqCard() -> NSView {
        let row = NSStackView(views: [])
        row.spacing = 2
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        row.layer?.cornerRadius = 8
        row.layer?.borderWidth = 1
        row.layer?.borderColor = Theme.border.cgColor
        row.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (i, label) in ["Ultimate", "Bass", "Vocal"].enumerated() {
            let b = pillButton(label, index: i, action: #selector(eqPillTapped(_:)))
            eqPillButtons.append(b)
            row.addArrangedSubview(b)
        }
        applyPillSelection(eqPillButtons, selected: 1)

        let note = NSTextField(labelWithString:
            "Presets verified live. Custom graphic bands exist in the protocol (cmd 0x432) but the payload format is not decoded yet.").with {
            $0.font = .systemFont(ofSize: 10)
            $0.textColor = Theme.white(0.35)
        }
        let head = cardHeader(icon: "slider.horizontal.3", tint: .systemGreen, title: "EQUALIZER",
                              note: "cmd 0x406", trailing: row)
        let body = NSStackView(views: [head, note])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        return wrapCard(body)
    }

    @objc private func eqPillTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let i = Int(raw),
              i < EQMode.allCases.count else { return }
        applyPillSelection(eqPillButtons, selected: i)
        bt.setEQ(mode: EQMode.allCases[i])
    }

    private func gameCard() -> NSView {
        gameSwitch.controlSize = .small
        gameSwitch.target = self
        gameSwitch.action = #selector(gameSwitched(_:))
        gameStatusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        gameStatusLabel.textColor = Theme.white(0.4)

        let head = NSStackView(views: [
            cardHeader(icon: "gamecontroller", tint: .systemYellow, title: "LOW LATENCY GAME SOUND",
                       note: "cmd 0x423", trailing: nil),
            NSView(),
            gameSwitch
        ])
        let row = NSStackView(views: [
            NSTextField(labelWithString: "Buffer:").with {
                $0.textColor = Theme.white(0.35); $0.font = .systemFont(ofSize: 11)
            },
            gameStatusLabel,
            NSView()
        ])
        let body = NSStackView(views: [head, row])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        return wrapCard(body)
    }

    @objc private func gameSwitched(_ sender: NSSwitch) {
        gameOn = sender.state == .on
        bt.setGame(on: gameOn)
        if gameOn {
            latencyPill.stringValue = "47ms (game)"
            latencyPill.textColor = Theme.green
            gameStatusLabel.stringValue = "low-latency buffer requested"
            gameStatusLabel.textColor = Theme.green
        } else {
            latencyPill.stringValue = "standard latency"
            latencyPill.textColor = Theme.white(0.5)
            gameStatusLabel.stringValue = "standard buffer"
            gameStatusLabel.textColor = Theme.white(0.4)
        }
    }

    private func diagnosticsCard() -> NSView {
        let buttonRow = NSStackView(views: [
            diagButton("Read device info", #selector(readInfoTapped)),
            diagButton("Read RSSI", #selector(readRSSITapped)),
            diagButton("Switch inventory (0x503)", #selector(readSwitchesTapped)),
            diagButton("Capability map", #selector(readCapabilityTapped))
        ])
        buttonRow.spacing = 8

        terminalView.frame = NSRect(x: 0, y: 0, width: 620, height: 24)
        terminalView.isVerticallyResizable = true
        terminalView.isHorizontallyResizable = false
        terminalView.autoresizingMask = [.width]
        terminalView.isEditable = false
        terminalView.drawsBackground = false
        terminalView.textContainerInset = NSSize(width: 8, height: 6)
        terminalView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let termScroll = NSScrollView()
        termScroll.documentView = terminalView
        termScroll.hasVerticalScroller = true
        termScroll.translatesAutoresizingMaskIntoConstraints = false

        let termHeader = NSStackView(views: [
            miniDot(Theme.green),
            NSTextField(labelWithString: "WIRE LOG").with {
                $0.font = .monospacedSystemFont(ofSize: 10, weight: .bold); $0.textColor = Theme.white(0.4)
            },
            NSView(),
            clearButton()
        ])
        termHeader.spacing = 6
        termHeader.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        termHeader.wantsLayer = true
        termHeader.layer?.backgroundColor = Theme.white(0.04).cgColor

        let termBox = NSStackView(views: [termHeader, termScroll])
        termBox.orientation = .vertical
        termBox.spacing = 0
        termBox.wantsLayer = true
        termBox.layer?.backgroundColor = Theme.terminalBg.cgColor
        termBox.layer?.cornerRadius = 8
        termBox.layer?.borderWidth = 1
        termBox.layer?.borderColor = Theme.border.cgColor
        termScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        cmdField.placeholderString = "cmd hex"
        cmdField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        payloadField.placeholderString = "payload hex"
        payloadField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        jsonField.placeholderString = #"JSON: {"cmd":"get_tws_rssi"}"#
        jsonField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        let rawRow = NSStackView(views: [cmdField, payloadField, diagButton("Send", #selector(sendRawTapped))])
        rawRow.spacing = 6
        cmdField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        payloadField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let jsonRow = NSStackView(views: [jsonField, diagButton("Send JSON", #selector(sendJSONTapped))])
        jsonRow.spacing = 6
        jsonField.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        grantedLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        grantedLabel.textColor = Theme.white(0.35)

        let head = cardHeader(icon: "info.circle", tint: .systemBlue, title: "DIAGNOSTICS & RAW TELEMETRY",
                              note: "JSON channel 0xF03", trailing: buttonRow)
        let body = NSStackView(views: [head, termBox, grantedLabel, rawRow, jsonRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        return wrapCard(body)
    }

    // MARK: - Builders

    private func diagButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }

    private func clearButton() -> NSButton {
        let b = NSButton(title: "Clear", target: self, action: #selector(clearLogTapped))
        b.isBordered = false
        b.controlSize = .mini
        b.contentTintColor = Theme.accent
        return b
    }

    private func cardHeader(icon: String, tint: NSColor, title: String, note: String, trailing: NSView?) -> NSView {
        let chip = imageView(icon, tint: tint, size: 12).with {
            $0.wantsLayer = true
            $0.layer?.backgroundColor = tint.withAlphaComponent(0.2).cgColor
            $0.layer?.cornerRadius = 6
        }
        chip.widthAnchor.constraint(equalToConstant: 24).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let titleField = NSTextField(labelWithString: title).with {
            $0.font = .systemFont(ofSize: 11, weight: .bold)
            $0.textColor = Theme.white(0.85)
        }
        let noteField = NSTextField(labelWithString: note).with {
            $0.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            $0.textColor = Theme.white(0.35)
        }
        let text = NSStackView(views: [titleField, noteField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        let row = NSStackView(views: [chip, text, NSView()])
        if let trailing {
            row.addArrangedSubview(trailing)
        }
        row.spacing = 8
        return row
    }

    private func wrapCard(_ content: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.cardBg.withAlphaComponent(0.6).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.border.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 14)
        ])
        return container
    }

    private func pillButton(_ label: String, index: Int, action: Selector) -> NSButton {
        let b = NSButton(title: label, target: self, action: action)
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.identifier = NSUserInterfaceItemIdentifier(String(index))
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        applyPillStyle(b, selected: false)
        return b
    }

    private func applyPillSelection(_ pills: [NSButton], selected: Int) {
        for (i, b) in pills.enumerated() {
            applyPillStyle(b, selected: i == selected)
        }
    }

    private func applyPillStyle(_ b: NSButton, selected: Bool) {
        b.layer?.backgroundColor = selected ? Theme.white(0.15).cgColor : NSColor.clear.cgColor
        b.attributedTitle = NSAttributedString(
            string: b.title,
            attributes: [
                .foregroundColor: selected ? NSColor.white : Theme.white(0.55),
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium)
            ])
    }

    private func imageView(_ symbol: String, tint: NSColor, size: CGFloat) -> NSImageView {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        let iv = NSImageView()
        iv.image = img
        iv.contentTintColor = tint
        return iv
    }

    private func miniDot(_ color: NSColor) -> NSView {
        tintedDot(color)
    }

    private func versionChip() -> NSView {
        NSTextField(labelWithString: "v0.1.0").with {
            $0.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            $0.textColor = Theme.white(0.4)
            $0.wantsLayer = true
            $0.layer?.backgroundColor = Theme.white(0.05).cgColor
            $0.layer?.cornerRadius = 4
            $0.layer?.borderWidth = 1
            $0.layer?.borderColor = Theme.border.cgColor
        }
    }

    private func spacer(_ width: CGFloat) -> NSView {
        let v = NSView()
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    // MARK: - Actions

    @objc private func mainConnectTapped() {
        if bt.isConnected { bt.disconnect() } else { bt.connect() }
    }

    @objc private func pairedRowTapped(_ sender: NSButton) {
        guard let address = sender.identifier?.rawValue else { return }
        bt.selectedAddress = address
        refreshSidebarSelection()
    }

    @objc private func readInfoTapped() { bt.requestDeviceInfo() }
    @objc private func readRSSITapped() { bt.requestRSSI() }
    @objc private func readSwitchesTapped() { bt.refreshSwitchInventory() }
    @objc private func readCapabilityTapped() { bt.refreshCapability() }
    @objc private func clearLogTapped() { bt.logLines = []; renderedLogCount = 0; terminalView.string = "" }

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

    // MARK: - Subscriptions

    private func subscribe() {
        bt.$pairedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.deviceRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for dev in devices {
                    self.deviceRowsStack.addArrangedSubview(self.pairedRow(dev))
                }
                self.refreshSidebarSelection()
            }
            .store(in: &cancellables)

        bt.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let connected = state == .connected
                switch state {
                case .idle: self.statusDot.contentTintColor = .systemGray; self.statusLabel.stringValue = "Not connected"
                case .connecting: self.statusDot.contentTintColor = .systemOrange; self.statusLabel.stringValue = "Connecting..."
                case .connected: self.statusDot.contentTintColor = .systemGreen; self.statusLabel.stringValue = "Connected"
                case .failed(let m): self.statusDot.contentTintColor = .systemRed; self.statusLabel.stringValue = "Failed: \(m)"
                }
                self.deviceStatusLabel.stringValue = connected ? "ACTIVE & CONNECTED" : "OFFLINE"
                self.deviceStatusLabel.textColor = connected ? Theme.green : Theme.orange
                self.sidebarConnectButton.title = connected ? "Disconnect" : "Connect"
                self.ancPillButtons.forEach { $0.isEnabled = connected }
                self.eqPillButtons.forEach { $0.isEnabled = connected }
                self.gameSwitch.isEnabled = connected
            }
            .store(in: &cancellables)

        bt.$logLines
            .receive(on: RunLoop.main)
            .sink { [weak self] lines in
                guard let self else { return }
                let ts = self.terminalView
                if lines.count < self.renderedLogCount {
                    ts.string = ""
                    self.renderedLogCount = 0
                }
                for i in self.renderedLogCount..<lines.count {
                    let l = lines[i]
                    let s = NSMutableAttributedString()
                    s.append(NSAttributedString(string: "[\(l.time)] ", attributes: [
                        .foregroundColor: Theme.white(0.3),
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                    ]))
                    s.append(NSAttributedString(string: l.tag.uppercased() + " ", attributes: [
                        .foregroundColor: l.color,
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                    ]))
                    s.append(NSAttributedString(string: l.text + "\n", attributes: [
                        .foregroundColor: Theme.white(0.75),
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                    ]))
                    ts.textStorage?.append(s)
                }
                self.renderedLogCount = lines.count
                ts.scrollRangeToVisible(NSRange(location: (ts.string as NSString).length, length: 0))
            }
            .store(in: &cancellables)

        bt.$deviceInfo
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self, !info.isEmpty else { return }
                let s = NSMutableAttributedString()
                s.append(NSAttributedString(string: "device info ", attributes: [
                    .foregroundColor: NSColor.systemPurple,
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                ]))
                for key in info.keys.sorted() {
                    s.append(NSAttributedString(string: "\(key)=\(info[key] ?? "")  ", attributes: [
                        .foregroundColor: Theme.white(0.7),
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                    ]))
                }
                s.append(NSAttributedString(string: "\n", attributes: [.foregroundColor: Theme.white(0.7)]))
                self.terminalView.textStorage?.append(s)
                self.terminalView.scrollRangeToVisible(NSRange(location: (self.terminalView.string as NSString).length, length: 0))
            }
            .store(in: &cancellables)

        bt.$grantedCommands
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in
                guard let self, !granted.isEmpty else { return }
                self.grantedLabel.stringValue = "granted: " + granted.joined(separator: " ")
            }
            .store(in: &cancellables)

        bt.$ancMask
            .receive(on: RunLoop.main)
            .sink { [weak self] mask in
                guard let self else { return }
                self.ancMaskLabel.stringValue = mask == 0 ? "mask 0x----" : String(format: "mask 0x%04X", mask)
            }
            .store(in: &cancellables)

        bt.$eqMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if let idx = EQMode.allCases.firstIndex(where: { $0.rawValue == mode }) {
                    self.applyPillSelection(self.eqPillButtons, selected: idx)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Helpers

extension NSStackView {
    func with(_ configure: (NSStackView) -> Void) -> NSStackView {
        configure(self)
        return self
    }
}

extension NSTextField {
    func with(_ configure: (NSTextField) -> Void) -> NSTextField {
        configure(self)
        return self
    }
}

extension NSImageView {
    func with(_ configure: (NSImageView) -> Void) -> NSImageView {
        configure(self)
        return self
    }
}
