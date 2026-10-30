> **Superseded by [`ble_protocol.md`](ble_protocol.md).**
>
> This document described the GATT contract as planned before BLE was
> implemented. The implemented protocol — UUIDs, packet format, validation
> rules — now lives in `ble_protocol.md`, and the UUID constants it documents
> are the ones actually compiled into `lib/domain/ble/ble_protocol.dart`.
> Where the two disagree, `ble_protocol.md` is correct. Kept for design
> history.

# BLE architecture

The ESP32 hardware is not part of this phase. The app runs entirely on
`DemoPhysiologicalDataSource`. This document fixes the contract so the firmware
can be written now and the app side is a single file plus one dependency later.

## Target chain

```
Electrodes ─▶ AD8232 ─▶ ESP32 ─▶ R-peak detection ─▶ R-R intervals
                                        │
                                        ▼
                            HRV features (hr, meanRR, rmssd, sdnn, pnn50)
                                        │
                                     BLE GATT
                                        │
                                        ▼
                        BlePhysiologicalDataSource (Flutter)
                                        │
                                        ▼
                            StressPredictionService
```

**Feature computation happens on the ESP32, not in the app.** The phone
receives a finished feature vector. This keeps the BLE payload tiny, keeps the
app identical whether data is simulated or real, and means the raw ECG never
has to leave the device.

## The interface

```dart
abstract class PhysiologicalDataSource {
  String get id;                 // "demo" | "ble"
  String get displayName;        // shown on the measure screen
  String get sourceTag;          // DEMO | BLE, written onto every feature set
  DataSourceStatus get status;
  bool get isReady;

  Future<void> connect();
  Future<void> disconnect();
  Stream<MeasurementTick> measure(Duration duration);
  Future<PhysiologicalFeatures> readFeatures();
}
```

`MeasureController` talks only to this interface. It already handles the error
path: `BlePhysiologicalDataSource` currently returns an error stream, and
`measure_controller_test.dart` asserts the UI surfaces that as a message rather
than crashing.

## GATT contract

These identifiers are declared as constants on `BlePhysiologicalDataSource` and
pinned by a test, so changing one is a breaking change:

| Item | Value |
| --- | --- |
| Advertised name prefix | `NeuroPulse-` |
| Service UUID | `6e1a0001-b5a3-f393-e0a9-e50e24dcca9e` |
| Live vitals (notify) | `6e1a0002-b5a3-f393-e0a9-e50e24dcca9e` |
| Features (notify) | `6e1a0003-b5a3-f393-e0a9-e50e24dcca9e` |
| Control (write) | `6e1a0004-b5a3-f393-e0a9-e50e24dcca9e` |

### Live vitals characteristic — notify, ~10 Hz

Streamed while a measurement is running. Little-endian, 8 bytes:

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0 | `uint16` | `hr_milli_bpm / 10` | Heart rate ×10, e.g. 725 = 72.5 BPM |
| 2 | `uint16` | `rr_ms` | Latest R-R interval, ms |
| 4 | `uint8` | `signal_quality` | 0 poor, 1 fair, 2 good |
| 5 | `int8` | `waveform_sample` | −127..127, scaled to −1..1 for the trace |
| 6 | `uint16` | `elapsed_ms / 10` | Time since the measurement started |

### Features characteristic — notify, once per measurement

Sent when the measurement window closes. Little-endian, 12 bytes:

| Offset | Type | Field | Scaling |
| --- | --- | --- | --- |
| 0 | `uint16` | `hr` | ×10 BPM |
| 2 | `uint16` | `mean_rr` | ms |
| 4 | `uint16` | `rmssd` | ×10 ms |
| 6 | `uint16` | `sdnn` | ×10 ms |
| 8 | `uint16` | `pnn50` | ×10 % |
| 10 | `uint8` | `beats_used` | Beats in the window |
| 11 | `uint8` | `quality_flags` | Bit 0 set = usable window |

`quality_flags` bit 0 clear means the window was too noisy; the app should
report a poor-signal error rather than saving a session.

### Control characteristic — write

| Byte 0 | Command | Bytes 1-2 |
| --- | --- | --- |
| `0x01` | Start measurement | `uint16` duration in seconds |
| `0x02` | Stop measurement | — |
| `0x03` | Report status | — |

## Steps to enable BLE

1. **Add the dependency.**

   ```yaml
   dependencies:
     flutter_blue_plus: ^1.32.0
   ```

2. **Add platform permissions.**

   *Android* — `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                    android:usesPermissionFlags="neverForLocation" />
   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
   ```

   *iOS* — `ios/Runner/Info.plist`:

   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>NeuroPulse connects to your ECG sensor to read heart rhythm.</string>
   ```

3. **Implement the methods** in `ble_physiological_data_source.dart`:
   scan for `NeuroPulse-`, connect, discover the service, subscribe to both
   notify characteristics, write `0x01` with the duration to start, map live
   packets to `MeasurementTick` and the final packet to
   `PhysiologicalFeatures` with `source: DataSourceTag.ble`.

4. **Flip the composition root** so `activeDataSource` returns the BLE source
   when a device is paired and demo mode is off, falling back to the demo
   source otherwise.

5. **Add a device pairing screen** under `features/settings/`, and update the
   Profile "Device" row, which currently reads `Not connected`.

No other file needs to change. The measure screen, result screen, history and
prediction engine already consume the interface.

## Keeping demo mode

The demo source stays in the codebase after the hardware works. It makes the
app demonstrable without a sensor, keeps the widget tests device-free, and is
what the Demo Mode switch in Settings turns back on.
