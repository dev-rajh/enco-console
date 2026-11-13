import Foundation

/// OPPO Enco vendor protocol: framing, command IDs, payload builders.
/// Wire format (little-endian, confirmed on-device):
///   AA | totalLen(1) | 00 00 | cmdId LE16 | seq(1) | payloadLen LE16 | payload
/// Responses carry cmdId | 0x8000; poll-style replies start with a status byte
/// (0x00 = ok, 0xFF = unsupported). Diagnostic JSON pushes arrive on cmd 0x0300.
enum Cmd {
    static let capabilityGet      = 0x0100  // rsp: [status, bitmap...] LSB-first, 69 bits
    static let ancGet             = 0x010C
    static let ancSet             = 0x0404  // payload [type=01, count=01, mask LE16]
    static let eqGet              = 0x010F  // rsp: [status, mode]
    static let eqSet              = 0x0406  // payload [mode]
    static let gameSet            = 0x0423  // payload [type, 0|1]
    static let gameToggle         = 0x0434  // payload [0|1]
    static let featureSwitchSet   = 0x0403  // payload [featureId, 0|1]
    static let featureSwitchGet   = 0x0503  // rsp: [count, [id, status]...]
    static let diagJSON           = 0x0F03  // payload: UTF-8 JSON containing "cmd"
}

/// ANC bitmask bits (confirmed live on an Enco Air 5 Pro).
enum ANCBit {
    static let transparency: UInt16 = 0x0001
    static let smart: UInt16        = 0x0004  // "Smart (Wind noise reduction)" - untested
    static let off: UInt16          = 0x0008
    static let noiseCancel: UInt16  = 0x0010
}

/// EQ preset modes.
enum EQMode: UInt8, CaseIterable, Identifiable {
    case ultimate = 0x00
    case bass = 0x01
    case vocal = 0x02
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .ultimate: return "Ultimate"
        case .bass: return "Bass"
        case .vocal: return "Vocal"
        }
    }
}

/// Frame encoding.
enum Frame {
    static func encode(cmd: Int, seq: UInt8, payload: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(8 + payload.count)
        out.append(0xAA)
        out.append(UInt8(7 + payload.count))  // 2 zeros + cmd2 + seq + len2 + payload
        out.append(0x00)
        out.append(0x00)
        out.append(UInt8(cmd & 0xFF))
        out.append(UInt8((cmd >> 8) & 0xFF))
        out.append(seq)
        out.append(UInt8(payload.count & 0xFF))
        out.append(UInt8((payload.count >> 8) & 0xFF))
        out.append(contentsOf: payload)
        return out
    }
}

/// ANC payload [01, 01, maskLo, maskHi].
enum Payloads {
    static func anc(mask: UInt16) -> [UInt8] {
        [0x01, 0x01, UInt8(mask & 0xFF), UInt8((mask >> 8) & 0xFF)]
    }
    static func eq(_ mode: EQMode) -> [UInt8] { [mode.rawValue] }
    static func game(on: Bool) -> [UInt8] { [0x01, on ? 0x01 : 0x00] }
    static func json(_ string: String) -> [UInt8] { Array(string.utf8) }
}

struct DecodedFrame {
    let cmd: Int
    let payload: [UInt8]
}

/// Incremental stream parser. Matches the AA-framed little-endian format.
/// Resynchronizes by clearing the buffer whenever the first byte is not 0xAA.
final class FrameParser {
    private var buf: [UInt8] = []

    func feed(_ bytes: [UInt8]) -> [DecodedFrame] {
        buf.append(contentsOf: bytes)
        var frames: [DecodedFrame] = []
        while buf.count >= 2 && buf[0] == 0xAA {
            let n = Int(buf[1])
            guard buf.count >= 2 + n else { break }
            let f = Array(buf[2..<(2 + n)])
            buf.removeFirst(2 + n)
            guard f.count >= 5 else { continue }
            let cmd = Int(f[0]) | (Int(f[1]) << 8)
            let plen = Int(f[3]) | (Int(f[4]) << 8)
            guard f.count >= 5 + plen else { continue }
            frames.append(DecodedFrame(cmd: cmd, payload: Array(f[5..<(5 + plen)])))
        }
        if let first = buf.first, first != 0xAA {
            buf.removeAll()
        }
        return frames
    }

    func reset() { buf.removeAll() }
}

/// Capability bitmap table: bit i of the 0x100 reply grants these command IDs.
let capabilityTable: [[Int]] = [
    [0x0105], [0x0106], [0x0107], [0x0108, 0x0401, 0x0416], [0x0109], [0x0400], [0x0402],
    [0x0403], [0x010C, 0x0404], [0x0405], [0x0406, 0x010F], [0x0407], [], [0x0408], [0x0409],
    [], [], [0x0114], [], [0x040E, 0x040D, 0x0115, 0x0116], [0x040F], [0x0410, 0x0119], [0x0205],
    [0x0F00], [], [0x0118, 0x0411], [0x011A, 0x0412], [0x011C, 0x0413], [], [0x0112, 0x040B],
    [0x011E, 0x011F, 0x0415], [0x040D], [], [0x0121, 0x0417], [0x0122, 0x0418], [0x0419],
    [0x011D, 0x0414], [0x0123, 0x041A], [0x0124, 0x041B], [0x0125, 0x041C, 0x0127, 0x041D, 0x041F],
    [0x0421, 0x0023, 0x0024, 0x0022, 0x0126, 0x0129], [0xEEC1], [0xEEC2], [0xEEC3, 0x041E],
    [0x0420], [0x001C], [], [0x0422, 0x012A], [0xEEC4], [0x0423, 0x012B], [], [0x0424], [0xEEC6],
    [], [], [0x0425, 0x012E, 0x0426], [0x012F], [0x0427], [0x0428], [0x0431, 0x0429], [0x0432],
    [0x042D], [0x012F], [0xEEC7], [0xEEC8, 0x0136, 0x0433], [0xEEC9], [0x0431, 0x0134],
    [0x0432, 0x0135, 0x0435], [0x0117]
]

/// Decode a 0x100 capability reply into granted command IDs (hex strings).
func decodeCapability(payload: [UInt8]) -> [String] {
    guard let status = payload.first, status == 0x00, payload.count > 1 else { return [] }
    let bits = min((payload.count - 1) * 8, capabilityTable.count)
    var granted: [String] = []
    for i in 0..<bits {
        let bit = (payload[1 + i / 8] >> (i % 8)) & 0x01
        if bit == 1 {
            for cmd in capabilityTable[i] {
                granted.append(String(format: "0x%04X", cmd))
            }
        }
    }
    return granted
}
