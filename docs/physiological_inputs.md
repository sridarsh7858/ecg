# Physiological inputs

Everything the app consumes, and the rules that govern it.

## The one model

`PhysiologicalInputPacket` (`lib/data/models/physiological_input_packet.dart`)
is the single container. Demo, Manual and Bluetooth all produce one, and
**nothing downstream knows which produced it.**

```
Demo   ─┐
Manual ─┼─▶ PhysiologicalInputPacket ─▶ StressFeatureVector ─▶ engine ─▶ Level 1–5 ─▶ game
BLE    ─┘
```

## Every field is nullable, and that is load-bearing

The wearable may ship with an AD8232 and nothing else, gain GSR later, and never
get a gyroscope. So:

- **A missing sensor stays missing.** Absent is never rewritten to zero. Zero is
  a real reading for GSR, movement and pNN50 — collapsing the two would turn "no
  sensor" into "measured zero".
- The UI renders absent as **"Not available"**.
- In **Bluetooth mode nothing is ever substituted.** Demo mode simulates the
  optional sensors (clearly labelled), because its whole job is to exercise the
  UI; Bluetooth mode shows you what the hardware actually sent.

## Contents

| Group | Fields |
| --- | --- |
| ECG | `rawEcgSamples`, `rPeaks`, `rrIntervals`, `heartRate` |
| HRV | `meanRR`, `rmssd`, `sdnn`, `pnn50` |
| GSR / EDA | `gsrValue`, `gsrLevel`, `gsrPeaks` |
| Accelerometer | `accelX/Y/Z`, `movementIntensity` |
| Gyroscope | `gyroX/Y/Z` |
| Battery | `batteryVoltage`, `batteryCurrent`, `batteryPercentage` |
| Context | `userStressRating`, `sessionContext` |
| Meta | `timestamp`, `source`, `signalQuality` |

### Derived, not invented

Two values are computed when absent, because they are arithmetic identities, not
guesses:

- `effectiveMeanRR` = `60000 / hr`
- `effectiveHeartRate` = `60000 / meanRR`

`effectiveMovementIntensity` is computed from the accelerometer as the deviation
of the acceleration magnitude from 1 g, so a device resting in **any**
orientation reads near zero. With no accelerometer it returns `null` — never a
fabricated "still".

## What each signal does and does not mean

This section is the scientific discipline of the project, and it is enforced in
code, not just documented.

**Heart rate is not stress.** Elevated HR accompanies exercise, caffeine,
standing up, illness and excitement. It is one input among several.

**GSR is not stress.** Electrodermal activity tracks sympathetic arousal, which
overlaps with stress but also with heat, excitement and physical activity. In
this build GSR is **carried, displayed and stored, but not scored** — see below.

**Movement is not stress.** This one matters most, because the correlation is
tempting and wrong. High movement means two things: the reading may contain
motion artefact, and the user was active. The app treats movement purely as
context and as a data-quality flag. When movement is high the app says the
signal *may be unreliable* — never that the user is stressed.

**HRV is not a diagnosis.** Reduced variability is associated with sympathetic
dominance at a population level. It says nothing definitive about an individual
on one 30-second window.

## Why GSR and movement are not scored yet

`FeatureRegistry` declares them and the app extracts them, but they are
**disabled by default** and neither engine uses them: the demo heuristic
explicitly declines to score them, and the trained model was never shown them -
WESAD's chest ECG is what `ml-1.0.0` learned from, so the shipped graph takes
exactly `hr, meanRR, rmssd, sdnn, pnn50` and would reject a wider vector at
startup.

That is deliberate. No dataset this project has trained on says how much GSR
should contribute or in which direction. Inventing a coefficient would produce a number
that looks principled and is not. They are plumbed end-to-end so that the moment
real data justifies a weight, enabling them is a one-line registry change and
nothing else in the app moves.

## Signal quality and artefact

`signalQuality` (0–1) comes from the firmware. `hasMotionArtefactRisk` is true
above 0.55 movement intensity. Both describe **how much to trust the reading**,
and are shown as such — they never feed the estimate.

## Source labelling

Every packet carries a `PhysiologicalSource`: `DEMO`, `MANUAL` or `BLE`. It is
stamped at creation, persisted with history, and displayed on every result.
`ManualPhysiologicalDataSource.submit` overwrites whatever it is handed with
`MANUAL`, so a typed value can never be recorded as a hardware reading — even by
mistake.

Sources are never mixed silently. There is a test for it.
