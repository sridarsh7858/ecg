# ESP32 integration

The hardware side of the contract. The app is ready; this is what the wearable
has to do.

## Chain

```
Electrodes ─▶ AD8232 ─▶ ESP32 ADC ─▶ filter ─▶ R-peak detect ─▶ R-R
   ─▶ HR / RMSSD / SDNN / pNN50 ─▶ JSON ─▶ BLE notify ─▶ Flutter app
                                                            │
   GSR ──────────────────────────────────────────────────────┤
   Accel / Gyro ─────────────────────────────────────────────┤
   Battery ──────────────────────────────────────────────────┘
```

**Derived features first.** The ESP32 computes HR and HRV on-device and sends
numbers, not waveforms. Raw ECG streaming is optional and can be added later
without touching the app.

## Sensors — all optional except ECG

| Sensor | Typical part | Required |
| --- | --- | --- |
| ECG front-end | AD8232 | yes |
| GSR / EDA | two-electrode skin conductance | no |
| Accelerometer + gyro | MPU-6050 / LSM6DS3 | no |
| Battery gauge | divider on ADC, or MAX17048 | no |

Ship what you have. The app uses capability detection: sensors are listed as
Active (data seen), Declared (advertised, nothing received yet) or Not present.
A board with only an AD8232 works today.

## What to implement

1. **Advertise** a name containing `NeuroPulse`, e.g. `NeuroPulse-ESP32`.
2. **Expose** the service and physiology characteristic from `ble_protocol.md`,
   with notify enabled.
3. **Sample** ECG at 250–500 Hz.
4. **Detect R-peaks** — bandpass roughly 5–15 Hz, then threshold with a
   refractory period of about 250 ms.
5. **Reject artefact** — drop R-R intervals outside ~300–2000 ms, and intervals
   deviating more than ~20 % from a running median.
6. **Compute over a 30 s window**, updating about 1 Hz:
   - `hr` = 60000 / mean R-R
   - `mean_rr` = mean of surviving intervals, ms
   - `sdnn` = standard deviation of intervals, ms
   - `rmssd` = RMS of successive differences, ms
   - `pnn50` = percentage of successive differences > 50 ms, **0–100**
7. **Send JSON**, omitting any field you do not have.

### Two things that are easy to get wrong

**pNN50 is a percentage.** Send 12.5, not 0.125. The app validates 0–100 and
will drop a fractional value as out of range.

**Successive differences must not bridge a rejected beat.** If you drop an
artefact, compact the array and then diff it, you manufacture a large difference
between two intervals that were never adjacent — inflating RMSSD and pNN50
exactly on the noisy windows where they are already least trustworthy. Keep a
validity mask and diff only genuinely adjacent surviving pairs.

## Window length must match the app

The app captures **30 seconds** (`MeasureController`). SDNN, RMSSD and pNN50 are
all window-length dependent, so a 30 s SDNN is simply not the same quantity as
the 5-minute SDNN most HRV literature reports. If you change the firmware
window, change the app's capture duration to match — and if a model is ever
trained, train it on the same window too.

## Minimal viable packet

```json
{"type":"physiology","timestamp":1720000000,"hr":82.0,"rmssd":34.2,"sdnn":41.8,"pnn50":12.5}
```

That is enough for a complete, correctly-labelled reading in the app.

## Bring-up order

1. Advertise and connect. The app's Devices screen lists you.
2. Notify `{"hr": 70}` on a timer. The device card should show "Streaming".
3. Open the developer panel — it shows the last packet, the extracted feature
   vector, and any rejected packets with reasons. Malformed JSON will not
   disconnect you; it will be counted and explained.
4. Add HRV fields, then optional sensors one at a time. Watch the Sensors list
   move each one from Declared to Active.
5. Add raw ECG last, if at all.

## Battery

Either send `battery` (0–100) in the physiology packet, or expose the Bluetooth
SIG Battery Service (`0x180F` / `0x2A19`) — the app reads both. If you send
neither, the app shows "Battery unavailable" rather than a fake percentage.

## Android permissions

Already declared in the app's manifest. Note that `BLUETOOTH_SCAN` is declared
`neverForLocation`, so Android 12+ users are not asked for location permission
just to use a heart sensor. Keep it that way: do not put location-derivable data
in your advertisement.

## Testing before hardware exists

`FakeBleService` simulates a wearable — scan, connect, capabilities, streaming,
malformed packets — with no radio involved. See `demo_mode.md`.
