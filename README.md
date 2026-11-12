# Enco Console

An open-source macOS companion app for OPPO Enco true wireless earbuds, tested on the
**Enco Air 5 Pro**. It does what the official HeyMelody app does for the basics, and then
some: noise control, equalizer, game sound, device diagnostics, and a full raw command
console that speaks the earbuds' vendor protocol directly.

Unofficial community tool. Not affiliated with or endorsed by OPPO.

## Features

- **Noise control** - Off, Noise cancel, Transparency, plus a Smart (wind noise reduction)
  mode that exists in the vendor protocol. Verified live against an Air 5 Pro.
- **Equalizer** - Ultimate / Bass / Vocal presets, with state read-back.
- **Game sound toggle** - the low-latency game mode command the vendor app uses.
- **Device info** - name, firmware version, case version, serial and more, read through the
  earbuds' JSON diagnostic channel (`get_earbuds_msg`, `get_tws_rssi`).
- **Feature switch inventory** - read-only query (0x503) of the switches the firmware
  actually exposes.
- **Raw console** - send any command ID and hex payload, or raw JSON over the diagnostic
  channel, and watch every byte on the wire in a live log. This is what makes the app a
  research tool, not just a settings panel.
- **Capability map** - reads the earbuds' 69-bit capability bitmap and lists every command
  your specific firmware grants.

The vendor protocol itself is documented in [docs/PROTOCOL.md](docs/PROTOCOL.md), reverse
engineered from the HeyMelody APK and confirmed with on-device traffic.

## Requirements

- macOS 13 or newer
- Swift toolchain: Apple Command Line Tools are enough (`xcode-select --install`);
  full Xcode is **not** required because the UI is AppKit-based
- OPPO Enco earbuds already paired to the Mac (any model that speaks this SPP protocol;
  Air 5 Pro is the tested reference)

## Build

```bash
git clone https://github.com/dev-rajh/enco-console.git
cd enco-console
swift build            # debug binary
```

To produce a proper `.app` bundle (release build, ad-hoc signed):

```bash
./Scripts/make_app.sh
open "build/Enco Console.app"
```

## Usage

1. Pair the earbuds with the Mac in System Settings > Bluetooth, as with any audio device.
2. Launch Enco Console. macOS asks for Bluetooth permission once; grant it.
3. Pick your earbuds from the device list (they are sorted to the top) and hit **Connect**.
   The app opens an RFCOMM serial channel to the earbuds' vendor service and reads the
   device info.
4. Use the controls. Every send and receive is printed in the log panel at the bottom;
   anything interesting can be selected and copied.

The last-used device address is remembered in `UserDefaults` so Connect works directly
next time. The earbuds can stay connected to your phone for audio at the same time; the
serial channel is independent of the audio link.

## How it works

The earbuds expose a classic Bluetooth SPP (RFCOMM) service alongside the audio profiles.
Enco Console opens that channel and speaks OPPO's vendor protocol:

- Frames are `AA | length | 00 00 | command-id (LE16) | seq | payload-length (LE16) | payload`
- Replies mirror the command ID with the high bit set and start with a status byte
- A 69-bit capability bitmap (poll 0x100) declares which commands this firmware supports
- A JSON diagnostic channel (0xF03) carries factory-style queries and results
- ANC modes are a bitmask (0x404): transparency 0x01, off 0x08, noise cancel 0x10

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for the full command table, capability map, and
live captures. The framing is compatible with the protocol family documented by the
[Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) project for earlier Enco
models.

## Verified vs unverified

| Feature | Status |
| --- | --- |
| Frame format, ANC set, ANC bitmask bits (off / NC / transparency) | verified on Air 5 Pro |
| EQ set + get (Ultimate / Bass / Vocal) | verified on Air 5 Pro |
| Game sound type/enable command | decoded from the vendor app, not yet verified live |
| Device info JSON, RSSI JSON | verified on Air 5 Pro |
| Feature switch read (0x503) | decoded from the vendor app, not yet verified live |
| Smart (wind) ANC bit | unverified; the mode exists in the vendor app's strings |
| Unknown command family 0xEEC1-0xEEC9 | granted by this firmware, semantics unknown |

## Privacy

- No device addresses, serials, or identifiers are hardcoded in the source.
- The app talks Bluetooth directly to your earbuds. No network access at all.
- The only thing persisted is the address of the device you connected to, stored locally
  in `UserDefaults`.

## Troubleshooting

- **"SPP service record not found"** - the selected paired device is not an Enco bud, or
  the SDP query has not finished yet; press Connect again.
- **Status `FF` in replies** - the firmware does not support that command. Harmless.
- **Nothing appears in the log** - make sure the buds are not actively using the vendor
  channel from another app, and that macOS Bluetooth permission was granted.
- **App won't open after downloading a zip** - it is ad-hoc signed, so Gatekeeper flags
  it: right-click > Open once, or clear the quarantine attribute:
  `xattr -d com.apple.quarantine "build/Enco Console.app"`

## Disclaimer

This software sends commands to your earbuds that the manufacturer's app does not expose.
The verified controls are the same ones HeyMelody itself sends. The raw console can send
anything, so treat it like a serial terminal for hardware: if you do not know what a
command does, do not send it. No warranty.

## License

MIT. See [LICENSE](LICENSE).
