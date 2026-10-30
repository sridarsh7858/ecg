# Manual mode

Type in physiological values and run the full app on them. This is what keeps
the project moving while the wearable does not exist.

## Using it

Measure → **Manual** → *Enter values* → fill the form → **ANALYZE**.

From there everything is identical to any other reading: a level 1–5, the
values behind it, a recommended game, a session in history.

## The form

Grouped so it does not overwhelm. Only **Cardiovascular** is expanded by
default.

| Group | Fields |
| --- | --- |
| Cardiovascular | Heart Rate\*, Mean R-R, RMSSD, SDNN, pNN50 |
| GSR / EDA | GSR level, GSR peaks |
| Movement | Accelerometer X/Y/Z, Gyroscope X/Y/Z |
| Device | Battery |
| Context | Stress rating (1–5), Session context |

\* the only required field.

### Blank means absent

A field left empty produces a packet with that field **null**, and the app shows
"Not available" — exactly as it does for a wearable with no such sensor. Blank is
never read as zero. This is the same rule the BLE path follows, so the two modes
behave identically.

**Mean R-R** is the one exception: left blank, it is computed as `60000 / HR`.
That is an arithmetic identity, not an invented reading.

### Validation

Each field is range-checked against the same bounds the BLE parser uses
(`ble_protocol.md`). An empty form cannot be analysed — the app will not produce
a reading out of nothing. There is a test for that.

## Quick Demo

Five buttons at the top of the form fill every field with values shaped like
that stress level. It saves typing when demonstrating the app or testing the
five levels.

These numbers are **illustrative and invented**. They are not medically
validated and not measurements. The app says so on screen when you use them, and
the resulting reading is still tagged `MANUAL`, because you supplied the values
regardless of how they got into the boxes.

## Labelling

Everything entered here is tagged `PhysiologicalSource.manual` and displayed as
**Manual**. `ManualPhysiologicalDataSource.submit()` overwrites whatever source
it is handed, so a manual value cannot be recorded as a hardware reading even by
programming error.

The app never claims it measured these values. It analysed values you gave it —
a distinction that matters both scientifically and for anyone reading the
history later.

## Where it fits

```
Manual form ─▶ PhysiologicalInputPacket(source: MANUAL)
            ─▶ StressFeatureVector
            ─▶ prediction engine
            ─▶ Level 1–5 ─▶ recommended game ─▶ history
```

Identical to the Demo and Bluetooth paths from the packet onward. See
`physiological_inputs.md`.
