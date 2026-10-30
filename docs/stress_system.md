# Stress system

## The five levels

NeuroPulse uses exactly five project-defined levels. They are a project scale,
not a clinical classification.

| # | Title | Description | Recommendation |
| --- | --- | --- | --- |
| 1 | Very Low | You are in a calm, settled state. | Maintain your relaxed state with a gentle activity. |
| 2 | Low | You seem relaxed with plenty of headroom. | A light, playful session will keep things steady. |
| 3 | Moderate | You are alert and engaged, with some tension building. | A short focus or breathing session can help you reset. |
| 4 | High | Your readings suggest you are carrying a fair bit of load. | Take a short calming break with guided breathing. |
| 5 | Very High | You appear to be under a lot of pressure right now. | Give yourself a longer guided breathing session. |

## Single source of truth

Everything about a level lives in `lib/domain/stress/stress_level.dart`:

```dart
StressLevelConfig.of(StressLevel.high)   // -> StressLevelInfo
StressLevelConfig.ofNumber(4)            // same, by number
StressLevelConfig.all                    // all five, ordered 1..5
```

`StressLevelInfo` carries the number, title, description, recommendation,
motivational line, suggested game ids, icon and the light/dark accent colours.
No screen hard-codes a level's title, colour or recommended game — renaming a
level or re-tuning a recommendation is a one-file change.

`StressLevel.fromNumber` clamps out-of-range input rather than throwing, so a
corrupt stored value cannot crash the app.

## Feature vector

Four HRV features, the same four the trained model will consume:

| Feature | Meaning | Unit |
| --- | --- | --- |
| `hr` | Heart rate | BPM |
| `meanRR` | Mean R-R interval | ms |
| `rmssd` | Root mean square of successive R-R differences | ms |
| `sdnn` | Standard deviation of N-N intervals | ms |
| `pnn50` | Percentage of successive R-R intervals differing by >50 ms | % |

Every vector is tagged with a `source` (`DEMO` or `BLE`) and a timestamp, so
history can always tell simulated data from sensor data.

## The demo scoring heuristic

`lib/domain/stress/stress_scoring.dart` maps a feature vector onto a single
0..1 "arousal score", then onto a level.

Each feature is normalised to 0..1 over a plausible adult range. Higher heart
rate reads as higher arousal; lower variability reads as higher arousal, so
RMSSD, SDNN and pNN50 are inverted:

```
hrScore     =     (hr    - 55) / (105 - 55)
rmssdScore  = 1 - (rmssd - 12) / (75  - 12)
sdnnScore   = 1 - (sdnn  - 18) / (90  - 18)
pnn50Score  = 1 - (pnn50 -  2) / (45  -  2)

score = 0.30·hrScore + 0.30·rmssdScore + 0.22·sdnnScore + 0.18·pnn50Score
```

The 0..1 score is bucketed into five equal bands:

```
0.0 ──── 0.2 ──── 0.4 ──── 0.6 ──── 0.8 ──── 1.0
   L1       L2       L3       L4       L5
```

Confidence is derived from how close the score sits to the centre of its band.
A score near a boundary is genuinely more ambiguous, so it reports lower
confidence. The result is bounded to a believable 0.62 … 0.96.

> This is a transparent heuristic for demonstrating the application. It is not
> a validated physiological model, and it makes no clinical claim. The trained
> model replaces it entirely — see `future_ml_integration.md`.

## Why the demo is self-consistent

`DemoPhysiologicalDataSource` generates features by **inverting** the scoring
maths above. Ask it for level 4 and it picks a score near the centre of the
level-4 band, then solves back for HR, RMSSD, SDNN and pNN50, adding a little
independent noise so no two readings look identical.

```
requested level ──▶ band centre ──▶ inverse formulas ──▶ features
                                                            │
                                          StressScoring     │
                                                 ▲──────────┘
                                                 │
                                            same level
```

This is what makes the demo honest rather than a lie: the numbers on screen
genuinely produce the level being shown, and `dummy_stress_prediction_test.dart`
asserts the round trip holds for all five levels across many samples.

## Worked example

The example from the project brief:

```
HR 91 BPM, RMSSD 24 ms, SDNN 31 ms, pNN50 7%

hrScore    = (91 - 55) / 50    = 0.720
rmssdScore = 1 - (24 - 12)/63  = 0.810
sdnnScore  = 1 - (31 - 18)/72  = 0.819
pnn50Score = 1 - (7  -  2)/43  = 0.884

score = 0.30(0.720) + 0.30(0.810) + 0.22(0.819) + 0.18(0.884) = 0.798
      -> band 4  ->  Level 4, High
```

`dummy_stress_prediction_test.dart` pins this exact case.

## Personal baseline

The baseline is a short calm recording stored as `Baseline`. It is used for
**contextual visualisation only** — Home and Profile show baseline, current and
the difference. It is deliberately **not** fed into the prediction engine, so
personalisation can be added intentionally once a real model exists rather than
creeping in by accident.

## Language rules

The app never presents an estimate as a diagnosis. Copy uses "estimated stress
level", never "your stress is". Level 5 uses a muted rose accent rather than a
warning red, and every level carries an icon and a written label so the reading
never depends on colour alone. `stress_level_test.dart` asserts that no level's
copy contains alarming medical vocabulary.
