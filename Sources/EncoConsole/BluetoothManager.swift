import AppKit
import Foundation
import IOKit
import IOBluetooth
import Combine

/// SPP service UUID used by OPPO Enco earbuds for the vendor command channel.
/// This is a public protocol constant (also documented by the Gadgetbridge community),
/// not a secret or a device identifier.
private let sppUUIDString = "0000079A-D102-11E1-9B23-00025B00A5A5"

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

struct PairedDevice: Identifiable, Hashable {
    let address: String
    let name: String
    var id: String { address }
}

/// Owns the RFCOMM channel to the earbuds, encodes/decodes the vendor protocol,
/// and publishes UI state. All IOBluetooth work happens on the main thread /
/// main run loop, which is where the framework delivers delegate callbacks.
@MainActor
final class BluetoothManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published var pairedDevices: [PairedDevice] = []
    @Published var selectedAddress: String = UserDefaults.standard.string(forKey: "lastDeviceAddress") ?? ""
    @Published var state: ConnectionState = .idle
    @Published var logLines: [LogLine] = []
    @Published var deviceInfo: [String: String] = [:]
    @Published var grantedCommands: [String] = []
    @Published var ancMask: UInt16 = 0
    @Published var eqMode: UInt8 = 1

    var isConnected: Bool { state == .connected }
    var connectionLabel: String {
        switch state {
        case .idle: return "Not connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    // MARK: Internals

    private var channel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var seq: UInt8 = 0
    private let parser = FrameParser()

    private var uuidBytesBacking: [UInt8] = []

    private lazy var sppUUID: IOBluetoothSDPUUID? = {
        guard let base = UUID(uuidString: sppUUIDString) else { return nil }
        uuidBytesBacking = withUnsafeBytes(of: base.uuid) { Array($0) }
        // Kept alive in a stored property in case this initializer does not copy the bytes.
        return IOBluetoothSDPUUID(bytesNoCopy: &uuidBytesBacking, length: uuidBytesBacking.count)
    }()

    // MARK: Device discovery

    func refreshPairedDevices() {
        let all = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedDevices = all
            .compactMap { dev -> PairedDevice? in
                guard let addr = dev.addressString else { return nil }
                return PairedDevice(address: addr, name: dev.name ?? "Unknown")
            }
            .sorted { a, b in
                let aEnco = a.name.lowercased().contains("enco") || a.name.lowercased().contains("oppo")
                let bEnco = b.name.lowercased().contains("enco") || b.name.lowercased().contains("oppo")
                if aEnco != bEnco { return aEnco }
                return a.name < b.name
            }
    }

    // MARK: Connection

    func connect() {
        guard state != .connecting, state != .connected else { return }
        let address = selectedAddress
        guard !address.isEmpty else {
            log("Pick a paired device first.")
            return
        }
        UserDefaults.standard.set(address, forKey: "lastDeviceAddress")
        state = .connecting
        log("Connecting to \(address)...")
        Task { await connect(address: address) }
    }

    private func connect(address: String) async {
        guard let dev = IOBluetoothDevice(addressString: address) else {
            state = .failed("paired device not found")
            log("Device with address \(address) is not paired to this Mac.")
            return
        }
        device = dev
        guard let uuid = sppUUID else {
            state = .failed("bad service UUID constant")
            return
        }
        // Make sure we have the SDP record (needs a running run loop; we are on main).
        dev.performSDPQuery(nil)
        var record: IOBluetoothSDPServiceRecord?
        for _ in 0..<16 {
            record = dev.getServiceRecord(for: uuid)
            if record != nil { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        guard let rec = record else {
            state = .failed("SPP service record not found")
            log("The device does not advertise the Enco SPP service. Is it the right device?")
            return
        }
        var cid: BluetoothRFCOMMChannelID = 0
        let st = rec.getRFCOMMChannelID(&cid)
        guard st == kIOReturnSuccess else {
            state = .failed("no RFCOMM channel in service record")
            log("SDP record has no RFCOMM channel ID (status \(st)).")
            return
        }
        var ch: IOBluetoothRFCOMMChannel?
        // Blocks until the channel is open; data still arrives via the main run loop
        // through the delegate, so the UI stays responsive afterwards.
        let openStatus = dev.openRFCOMMChannelSync(&ch, withChannelID: cid, delegate: self)
        guard openStatus == kIOReturnSuccess, let opened = ch else {
            state = .failed("RFCOMM open failed (\(openStatus))")
            log("RFCOMM open failed with status \(openStatus).")
            return
        }
        opened.setDelegate(self)
        channel = opened
        parser.reset()
        state = .connected
        log("Connected on RFCOMM channel \(cid).")
        requestDeviceInfo()
    }

    func disconnect() {
        if let ch = channel {
            ch.close()
        }
        channel = nil
        device = nil
        if state != .idle { state = .idle }
        log("Disconnected.")
    }

    // MARK: Sending

    @discardableResult
    func send(cmd: Int, payload: [UInt8]) -> Bool {
        guard let ch = channel, isConnected else {
            log(String(format: "Not connected; nothing sent (cmd 0x%04X).", cmd))
            return false
        }
        var bytes = Frame.encode(cmd: cmd, seq: seq, payload: payload)
        seq = seq &+ 1
        let status = ch.writeSync(&bytes, length: UInt16(bytes.count))
        let ok = status == kIOReturnSuccess
        log(String(format: "%04X %@", cmd, payload.isEmpty ? "(empty)" : hex(payload)), tag: "TX", color: .systemGreen)
        if !ok { log("write failed, status \(status)") }
        return ok
    }

    func setANC(mask: UInt16) {
        send(cmd: Cmd.ancSet, payload: Payloads.anc(mask: mask))
    }

    func setEQ(mode: EQMode) {
        send(cmd: Cmd.eqSet, payload: Payloads.eq(mode))
    }

    func setGame(on: Bool) {
        send(cmd: Cmd.gameSet, payload: Payloads.game(on: on))
    }

    func refreshCapability() {
        send(cmd: Cmd.capabilityGet, payload: [])
    }

    func refreshANC() {
        send(cmd: Cmd.ancGet, payload: [])
    }

    func refreshEQ() {
        send(cmd: Cmd.eqGet, payload: [])
    }

    func refreshSwitchInventory() {
        send(cmd: Cmd.featureSwitchGet, payload: [])
    }

    func sendJSON(_ string: String) {
        send(cmd: Cmd.diagJSON, payload: Payloads.json(string))
    }

    func requestDeviceInfo() {
        sendJSON(#"{"cmd":"get_earbuds_msg"}"#)
    }

    func requestRSSI() {
        sendJSON(#"{"cmd":"get_tws_rssi"}"#)
    }

    // MARK: Logging

    /// Writes a startup line into the terminal so it is not empty on first launch.
    func announceReady() {
        log("ready; select your earbuds in the sidebar and press Connect", tag: "info", color: .systemTeal)
    }

    private func log(_ line: String, tag: String = "info", color: NSColor = .systemGray) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append(LogLine(time: stamp, tag: tag, text: line, color: color))
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    // MARK: Frame ingestion

    private func ingest(_ frames: [DecodedFrame]) {
        for f in frames {
            let isRsp = (f.cmd & 0x8000) != 0
            log(String(format: "%04X %@", f.cmd, f.payload.isEmpty ? "(empty)" : hex(f.payload)), tag: "RX", color: .systemBlue)

            if isRsp, let first = f.payload.first, first == 0xFF {
                log("unsupported by this firmware", tag: "status", color: .systemOrange)
            }

            switch f.cmd {
            case Cmd.capabilityGet | 0x8000:
                let granted = decodeCapability(payload: f.payload)
                grantedCommands = granted
                log("\(granted.count) commands granted", tag: "caps", color: .systemTeal)
            case Cmd.eqGet | 0x8000 where f.payload.count >= 2 && f.payload[0] == 0x00:
                eqMode = f.payload[1]
                log("  -> EQ mode \(f.payload[1])")
            case 0x0300:
                // Diagnostic JSON push: [00, 00, {json...}]
                if let brace = f.payload.firstIndex(of: 0x7B) {
                    let jsonBytes = Array(f.payload[brace...])
                    if let obj = try? JSONSerialization.jsonObject(with: Data(jsonBytes)),
                       let dict = obj as? [String: Any] {
                        var pretty: [String: String] = [:]
                        for (k, v) in dict { pretty[k] = "\(v)" }
                        deviceInfo = pretty
                        log("\(dict.count) fields", tag: "json", color: .systemPurple)
                    }
                }
            default:
                break
            }

            // ANC state pushes: [01, 01, maskLo, maskHi]
            if f.payload.count >= 4, f.payload[0] == 0x01, f.payload[1] == 0x01 {
                let mask = UInt16(f.payload[2]) | (UInt16(f.payload[3]) << 8)
                if mask != ancMask && mask != 0 {
                    ancMask = mask
                    log(String(format: "ANC mask 0x%04X", mask), tag: "push", color: .systemPurple)
                }
            }
        }
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate (selectors matched explicitly)

extension BluetoothManager {

    nonisolated func copyBytes(_ ptr: UnsafeMutableRawPointer?, _ len: Int) -> [UInt8] {
        guard let ptr = ptr, len > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: UInt8.self), count: len))
    }

    @objc(rfcommChannelOpenComplete:channelStatus:)
    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel?, status channelStatus: Int32) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if channelStatus == kIOReturnSuccess {
                self.state = .connected
                self.log("Connected. You can send commands now.")
                self.requestDeviceInfo()
            } else {
                self.state = .failed("open status \(channelStatus)")
                self.log("RFCOMM open-complete reported status \(channelStatus).")
                self.disconnect()
            }
        }
    }

    @objc(rfcommChannelData:data:length:)
    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel?, data ptr: UnsafeMutableRawPointer?, length len: Int) {
        let bytes = copyBytes(ptr, len)
        guard !bytes.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let frames = self.parser.feed(bytes)
            self.ingest(frames)
        }
    }

    @objc(rfcommChannelClosed:)
    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.channel = nil
            self.device = nil
            if self.state == .connected {
                self.state = .idle
                self.log("Channel closed by the device.")
            }
        }
    }
}
