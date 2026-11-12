# OPPO Enco Air 5 Pro vendor protocol (v2, confirmed)

Sources: HeyMelody APK static analysis (com.oplus.melody, decompiled `reference/heymelody-src/`),
Gadgetbridge old-gen protocol, and LIVE confirmation from user's working `enco.py` (RFCOMM from macOS,
IOBluetooth). User's script confirmed framing and ANC/EQ payloads on the real buds.

## Transport

- Classic Bluetooth SPP (RFCOMM), service UUID `0000079a-d102-11e1-9b23-00025b00a5a5`.
- Works from macOS via IOBluetooth (user's script), device <MAC redacted>.

## Wire frame (CONFIRMED by working enco.py)

OLD-GEN Gadgetbridge-compatible framing, NOT the new-gen BE format seen in Packet.java:

```
AA | totalLen(1) | 00 00 | cmdId LE16 | seq(1) | payloadLen LE16 | payload
totalLen counts everything after the length byte.
Response: same frame, cmdId = request | 0x8000.
```

Poll-style responses start with a STATUS byte: `00` = success, `FF` = command not supported/failed,
`06` = synthesized timeout status (PacketTimeoutProcessor). Decode every RX as `[status, data...]`.

## ANC (0x404) bitmask semantics (from live tests + strings)

Payload `[01, 01, bitmask...]` (type 1 = bitmask form). Bits observed:
- 0x01 = transparency
- 0x08 = off (user's "off" payload 08 00)
- 0x10 = ANC on
- "Smart (Wind noise reduction)" is an ANC MODE on capable models (string
  `melody_common_reduce_wind_noise_tip_new` = "Smart (Wind noise reduction)") - another bit in this
  mask, exact value untested (candidates: 0x04, 0x20, 0x40). Read current state with GET first.
- GET ANC state: poll **268 (0x10C)** (capability bit 8 pairs {268, 1028}).
- Level form: type 2 = `[02, level]` (CurrentNoiseModeInfo).

## EQ (0x406): `[mode]`, 0x00=ultimate, 0x01=bass, 0x02=vocal. GET: poll **271 (0x10F)**.

## Capability bitmap (the authoritative command list) - LIVE CONFIRMED

**Capability GET = poll 0x100 (256)** (confirmed live; earlier 0x107 claim was wrong).
Rsp: `[status, bitmap...]` LSB-first, up to 69 bits; bit i grants the commands in `B6.a.f680a[i]`
(Protocol.java). Observed reply (one unit): `00 ff 77 52 ea 24 0e 07 8f` -> bits set:
0-10, 12, 13, 14, 17, 20, 22, 25, 27, 29, 30, 31, 34, 37, 41, 42, 43, 48, 49, 50, 56-59, 63.
Granted highlights: ANC get/set (268/1028), EQ get/set (271/1030), feature switch (1027),
personalized ANC scan (286/287/1045), multi-notification (517), debug (3840), game (1059/299),
EEC1-EEC4 + EEC7. NOT granted: hearing suite (bit 19), tap settings (bit 44), auto-switch (bit 64),
zen custom (bits 38/39), EEC5/EEC6/EEC8/EEC9. Full table:

| bit | commands granted |
|-----|------------------|
|  0  | 261 (fw version get) |
|  1  | 262 |
|  2  | 263 (this poll) |
|  3  | 264, 1025 (0x401), 1046 (0x416) |
|  4  | 265 |
|  5  | 1024 (0x400) |
|  6  | 1026 (0x402) |
|  7  | 1027 (0x403 feature switch set) |
|  8  | 268 (0x10C ANC get), 1028 (0x404 ANC set) |
|  9  | 1029 |
| 10  | 1030 (0x406 EQ set), 271 (0x10F EQ get) |
| 11  | 1031 |
| 13  | 1032 |
| 14  | 1033 |
| 17  | 276 |
| 19  | 1038, 1037, 277, 278 |
| 20  | 1039 |
| 21  | 1040, 281 |
| 22  | 517 (multi-notification register) |
| 23  | 3840 (debug log level) |
| 25  | 280, 1041 |
| 26  | 282, 1042 |
| 27  | 284, 1043 |
| 29  | 274, 1035 |
| 30  | 286, 287 (ear scan filter get), 1045 (ear scan set) |
| 31  | 1037 |
| 33  | 289, 1047 |
| 34  | 290, 1048 |
| 35  | 1049 |
| 36  | 285, 1044 |
| 37  | 291, 1050 |
| 38  | 292, 1051 |
| 39  | 293, 1052, 295, 1053, 1055 |
| 40  | 1057, 34, 35, 36, 294, 297 |
| 41  | 61185 (0xEEC1) |
| 42  | 61186 (0xEEC2) |
| 43  | 61187 (0xEEC3), 1054 |
| 44  | 1056 (tap settings) |
| 45  | 28 |
| 47  | 1058, 298 |
| 48  | 61188 (0xEEC4) |
| 49  | 1059 (game type set), 299 (game get) |
| 51  | 1060 |
| 52  | 61190 (0xEEC6) |
| 55  | 1061, 302, 1062 |
| 56  | 303 |
| 57  | 1063, ModuleType.TYPE_BROWSER |
| 58  | 305, 1064 |
| 59  | 1065, 306 |
| 60  | 20 |
| 61  | 1069, 307 |
| 62  | 1070 |
| 63  | 61191 (0xEEC7) |
| 64  | 61192 (0xEEC8), 310, 1075 (auto-switch) |
| 65  | 61193 (0xEEC9) |
| 66  | 1073, 308 |
| 67  | 1074, 309, 1077 |
| 68  | 279 |

Always-allowed (no capability needed): 256-260, 262, 267, 269, 3840, 3843, 3844.
Async-permitted: 1038, 1037, 1041, 1045, 1047, 289, 1029, 3840, 3841, 3842, 3844, 3845.
0xEEC1..0xEEC7: granted by this firmware, silent on empty sends, semantics unknown, game-adjacent
(0xEEC8 checked by GameSetItem UI but NOT granted here).

## 0x50x family (RequestCommandManager; request id = rsp & 0x7FFF)

| req  | rsp wire | meaning |
|------|----------|---------|
| 0x501 | 0x8501 | generic device-info sync trigger (MSG 32) |
| 0x502 | 0x8502 | status byte sync (MSG 33) |
| 0x503 | 0x8503 | **feature switch status READ**: `[count, [id, status]...]` (CommandUtil.i). READ-ONLY probe for the hidden-switch question |
| 0x504 | 0x8504 | EQ mode get (EqualizerModeInfo) |
| 0x505 | 0x8505 | interrupt/break status, 2 bytes |
| 0x506 | 0x8506 | custom EQ list |
| 0x507 | 0x8507 | case exists, parse not read |

## Live probe results (the reference CLI script, sw_ver 158 / box_ver 105, unit SN <serial redacted>)

- 0x100 -> `00 ff 77 52 ea 24 0e 07 8f` = capability bitmap above.
- 0x10F -> `00 01` = EQ mode 01 (bass), matches last set. EQ GET works.
- 0x10C -> `02 c9 1c e5 09` = not obviously ANC state; treat as unusable, ANC state comes via pushes.
- 0x107 -> `00 02 01 03 02 00` = unknown, not decoded.
- 0x131 + [01] -> `00 00 00` (ok, empty values); 0x133/0x135 + [01] -> silence.
- 0xEEC1/EEC2/EEC3/EEC4/EEC7 empty sends -> complete silence (no rsp, no push).
- 0xF03 JSON -> works both directions. Diagnostic PUSH arrives on cmd 0x300 as `[00, 00, {json}]`.
  `get_earbuds_msg` returns right-bud identity: name, MAC, SN, hw_ver 0, sw_ver 158, box_ver 105,
  color 2, user_time (uptime counter, changes per call; buds truncate the JSON without closing brace).
- ANC set 0x404 bitmask bits: 0x01 transparency, 0x08 off, 0x10 ANC (live). "Smart (Wind noise
  reduction)" is an ANC mode name in the APK (string melody_common_reduce_wind_noise_tip_new);
  its bit value untested (candidates 04/20/40).

## Feature switches: set 1027 (0x403), payload `[featureId, 0|1]`

Known ids (app vocabulary): 4 = wear detection, 6 = game mode (mutex), 17 = multi-connection,
31 = LE audio (id 31 bypasses the capability check in the app; buds decide), 40 = game mode main
enable. The buds report their switch list in device-info responses as `[count, [id, status]...]`
(CommandUtil.i). NO call/ENC/wind switch id exists anywhere in app logic; unknown ids 0..63 can be
swept - buds answer status 00 for accepted, FF/err for unknown.

## Notification subsystem (0x200 range)

Register: 513 (0x201, single event), 517 (0x205, event list), capability query 512 (0x200) ->
rsp `[status, count, eventIds...]` (0x8200). Event id codes parsed in NotificationCommandManager.b():
-15 user interaction, -14 connect devices, 1/2 lists, **3 = ANC state change push (NoiseReductionInfo)**,
4 = ear-fit compactness detection, 5 = game mode, 6 = multi-connect status, 7/12/16 battery-ish,
8/9 zen mode switch, **10 = personalized ANC scan result**, 11 triangle, 13 public event, 14 oneshot,
15 tone change, 17 ear-tone list.

## Diagnosis JSON channel: set 3843 (0xF03), payload = UTF-8 JSON, must contain "cmd"

Request bean: `{"cmd": "..."}` (+ extra fields per test). Full id map (Constants.DiagnosisIdMapping):

READS (safe): get_sn(106100), get_earbuds_msg(106101), get_earbuds_temp(106102),
get_earbuds_temp_history(106103), get_earbuds_charge(106104), get_tws_rssi(106111),
get_box_charge(106112), get_box_temp(106113), get_box_temp_history(106114), get_box_usb_temp(106115),
get_box_usb_temp_history(106116), get_earbuds_charge_history(106117),
get_ear_bat_fast_drop_history(106118), get_ear_health_history(106119).

ACTIONS (state-changing, use with care): earbuds_mic(106150) = factory mic test,
ear_audio(106151), ear_volume(106152), box_cover(106153), ear_wear_control(106154),
box_light(106155), box_button(106156), ear_bat_fast_drop(106157), switch_role(106199),
enter_diagnostic(106198), quit_diagnostic(106197), factory_para_check(106105),
user_para_check(106106). Mic test JSON shape: `{"cmd":"earbuds_mic","earside":"left|right","data":"null"}`
(GSON bean fields cmd/earside/data).

Debug log level: 3840 (0xF00) payload `[deviceType, debugLevel, module]`. 0xF04 semantics unknown.

## Verdict on call ENC knobs

- Feature switches: no call id in app vocabulary. The buds' own switch inventory can be READ via
  GET 0x503 (rsp `[count, [id, status]...]`) without writing anything.
- Capability bitmap (live): NO call-noise/wind/voice command group exists anywhere in the granted
  set. Wind = "Smart" ANC mode bit. AI Clear Voice ("AI Clear Voice", "AI noise cancellation
  algorithm... enhanced call audio quality") has UI strings in the APK but ZERO protocol plumbing:
  no set/get, no switch, no event. On models that expose it, it is firmware, not this protocol.
- Diagnosis JSON: reads are identity/telemetry only; nothing exposes ENC state.
- CONCLUSION (findings verified live, 2026-11-12): call ENC on this unit is firmware-fixed. The
  protocol cannot change it. Remaining levers: a newer firmware if OPPO ever ships beyond sw 158
  (check HeyMelody), physical mitigations (tips, mic ports), replacement unit, host-side DSP
  (Mac only; Android is locked down).

## Remaining optional probes

1. GET 0x503 (empty payload) -> buds' own switch list `[count, [id, status]...]`. Read-only. If it
   lists only known ids (4/6/17/40), the hidden-switch question closes for good.
2. ANC bitmask: try Smart-mode bit candidates (04/20/40) one at a time via 0x404, revert after
   each. Affects user's own listening, not uplink ENC.
3. 0xEEC1..EEC7 with non-empty payloads: NOT recommended (unknown writes, no read-back).
4. Safe JSON reads via 0xF03 for the record: get_tws_rssi, get_earbuds_temp, get_sn.
