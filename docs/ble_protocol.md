# BLE protocol

The contract between the ESP32 firmware and the app. Everything here is
implemented in `mobile/lib/domain/ble/ble_protocol.dart` and pinned by
`mobile/test/ble_protocol_test.dart` — if a payload passes those tests, the app
accepts it.

## Transport

BLE GATT, JSON payloads, sent as characteristic notifications.

JSON rather than a packed binary struct, on purpose. A packed layout would be
smaller, but during firmware bring-up the ability to read a packet in a serial
monitor and in the app's developer panel is worth far more than the bytes. The
window is 30 s of derived features, not a raw stream, so payload size is not the
constraint. Moving to binary later is a change confined to one file.

## UUIDs

Defined once in `BleUuids` (`ble_protocol.dart`). **These are not final** — the
firmware does not exist yet. If you choose different ones, change them there and
nowhere else; nothing else in the app hard-codes a UUID.

| Role | UUID | Properties |
| --- | --- | --- |
| NeuroPulse service | `6e1a0001-b5a3-f393-e0a9-e50e24dcca9e` | — |
| Physiology | `6e1a0002-b5a3-f393-e0a9-e50e24dcca9e` | notify |
| Device info | `6e1a0003-b5a3-f393-e0a9-e50e24dcca9e` | read |
| Battery | `6e1a0004-b5a3-f393-e0a9-e50e24dcca9e` | notify |
| Raw ECG | `6e1a0005-b5a3-f393-e0a9-e50e24dcca9e` | notify |
| Control | `6e1a0006-b5a3-f393-e0a9-e50e24dcca9e` | write |

Alternatively the firmware may expose the Bluetooth SIG Battery Service
(`0x180F` / `0x2A19`); the app accepts either. UUID comparison is
case-insensitive and expands 16-bit short forms, because platforms disagree on
both.

Advertise a name containing **`NeuroPulse`** (e.g. `NeuroPulse-ESP32`). The app
scans without a service filter — a device whose advertisement is not yet right
would otherwise be invisible during bring-up — and sorts matching names first.

## Physiology packet

Only the `type` field is structural. **Every physiological field is optional.**

```json
{
  "type": "physiology",
  "timestamp": 1720000000,
  "hr": 82.0,
  "mean_rr": 731.7,
  "rmssd": 34.2,
  "sdnn": 41.8,
  "pnn50": 12.5,
  "gsr": 2.14,
  "gsr_peaks": 3,
  "accel_x": 0.02,
  "accel_y": 0.11,
  "accel_z": 0.98,
  "gyro_x": 0.01,
  "gyro_y": 0.03,
  "gyro_z": 0.02,
  "battery": 87,
  "signal_quality": 0.92
}
```

This is equally valid and is accepted:

```json
{ "hr": 82, "rmssd": 34.2 }
```

A missing field means **the sensor is not there**. It is never replaced with a
zero, because zero is a legitimate reading for several of these. The app shows
"Not available" instead.

### Fields

| Field | Unit | Accepted range | Notes |
| --- | --- | --- | --- |
| `hr` | BPM | 20 – 250 | also `heart_rate`, `heartRate` |
| `mean_rr` | ms | 200 – 3000 | derived from `hr` if omitted |
| `rmssd` | ms | 0 – 1000 | |
| `sdnn` | ms | 0 – 1000 | |
| `pnn50` | **%** | 0 – 100 | percentage, **not** 0–1 |
| `gsr` | µS | 0 – 1000 | `gsr_level` also accepted |
| `gsr_peaks` | count | 0 – 1000 | integer |
| `accel_x/y/z` | g | −16 – 16 | |
| `gyro_x/y/z` | dps | −2000 – 2000 | |
| `battery` | % | 0 – 100 | integer |
| `battery_voltage` | V | 0 – 12 | |
| `battery_current` | mA | −5000 – 5000 | |
| `signal_quality` | — | 0 – 1 | |
| `stress_rating` | 1–5 | 1 – 5 | user self-report, if the device collects it |
| `timestamp` | Unix s | — | see below |

`snake_case` is the documented spelling; `camelCase` is also accepted.

### Validation

A field outside its range is **dropped, and the rest of the packet is kept**. A
detached electrode reporting `hr: 0` alongside a good RMSSD must not cost you
the RMSSD. Dropped fields are reported in the developer panel.

A packet is rejected outright only when nothing recognisable survives. Rejection
never disconnects the link and never throws — malformed output from
half-finished firmware is an expected condition, not a crash.

### Timestamps

Send Unix seconds. An ESP32 with no RTC or NTP sync will send its uptime, which
would date every reading to 1970 and wreck the history chart, so the app
substitutes the phone's clock for any timestamp that is not plausibly recent
(roughly 2001–2100). Milliseconds are also detected.

## Device info

Read once on connect. All fields optional.

```json
{ "fw": "0.1.0", "hw": "rev-a", "sensors": ["ecg", "gsr", "accel", "battery"] }
```

Accepted sensor names: `ecg`/`hr`/`hrv`/`ad8232`, `gsr`/`eda`,
`accel`/`accelerometer`, `gyro`/`gyroscope`, `battery`, `raw_ecg`.

This is a *declaration*. The app also records which sensors have actually
delivered data, and shows both — a sensor declared but never seen shows as
"Declared" rather than "Active", which is exactly the state you want visible
while writing firmware.

## Raw ECG (optional)

Not required. The first firmware should send derived features only; streaming
250–500 Hz of ADC over BLE is a lot for a battery-powered board.

```json
{
  "type": "ecg",
  "timestamp": 1720000000,
  "sample_rate": 250,
  "seq": 42,
  "samples": [1234, 1250, 1288, 1302]
}
```

Raw ADC counts; the app does not assume a scale or resolution and normalises
against the observed range. Max 2000 samples per packet. `seq` is optional and
lets the app count dropped bursts. The app buffers the most recent ~6 s.

If no raw ECG arrives, the app shows **"ECG waveform unavailable"**. It never
draws a synthetic waveform in Bluetooth mode.

## What the firmware must do

1. Advertise a name containing `NeuroPulse`.
2. Expose the service and at minimum the physiology characteristic, with notify.
3. Compute HR and HRV on-device over a 30 s window and notify a packet
   periodically (1 Hz is ample).
4. Omit any field you do not have. Do not send zeros or placeholders.
5. Send `pnn50` as a percentage, 0–100.

See `esp32_integration.md` for the hardware side.
