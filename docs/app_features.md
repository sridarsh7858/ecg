# App features

## Screens

| Section | Screen | What it does |
| --- | --- | --- |
| Onboarding | `OnboardingScreen` | Four slides, skippable, shown once |
| Auth | `LoginScreen` | Sign in |
| Auth | `RegisterScreen` | Name, email, age, password |
| Auth | `ForgotPasswordScreen` | Reset request |
| Home | `HomeScreen` | Dashboard |
| Measure | `MeasureScreen` | The check-in flow |
| Measure | `StressResultScreen` | The result of a check-in |
| Games | `GamesScreen` | Activity picker |
| Games | five game screens | The playable activities |
| Games | `GameResultScreen` | Post-session before/after |
| History | `HistoryScreen` | Trends and session list |
| History | `SessionDetailScreen` | One session in full |
| Profile | `ProfileScreen` | Account, stats, baseline, system |
| Profile | `BaselineScreen` | Record a calm baseline |
| Settings | `SettingsScreen` | Preferences and data |
| Settings | `DeveloperPanelScreen` | Demo controls |
| Settings | `AboutScreen` | About, privacy, disclaimer |

## Onboarding

1. Welcome to NeuroPulse
2. Understand your current stress
3. Play calming experiences
4. Track your progress

Skip is available on every slide. Once completed the flag is persisted and it
never appears again.

## Accounts

Local, offline, behind `AuthRepository`. Registration collects a name, email,
age and password, and nothing else. Passwords are stored as a salted SHA-256
hash rather than plain text — adequate for a single-device prototype, and
explicitly not a substitute for a real identity provider.

Forgot-password validates that the account exists and then says plainly that
this build has no email backend, rather than pretending a message was sent.

## Home

- Time-aware greeting: "Good morning, Asha".
- **CURRENT STRESS** — an animated arc gauge showing the level number, written
  label and an icon, with confidence underneath.
- The level description and its recommendation.
- **Your readings** — Heart Rate, RMSSD, SDNN, pNN50, plus mean R-R. When a
  baseline exists, each tile also shows the difference against it.
- **Recommended for you** — the suggested game with a large PLAY NOW button.
- Three tappable stats: day streak, total check-ins, 7-day average.
- A "Demo data" badge wherever the values are simulated.

Pull to refresh regenerates the demo reading.

## Measure

```
START  ──▶  MEASURING  ──▶  PROCESSING  ──▶  RESULT
```

The ready state shows the device (`Demo Mode`), signal quality and the
configured duration. While measuring: a countdown, a progress bar, a live
ECG-style trace, and live HR, R-R and signal readouts. Processing runs the
engine. The result screen is then pushed.

Duration is configurable (15/30/45/60 s). Demo mode is labelled throughout.

## Stress result

The gauge, the level and its label, an "Estimated stress level" chip, then the
four HRV values. **View details** expands mean R-R, confidence, engine version,
data source and timestamp. Then the recommendation with **PLAY RECOMMENDED
GAME**, and **SAVE SESSION**.

Playing from here saves the check-in first, so the play-through is linked to it
and History can show a before/after pair.

## Games

See `game_system.md`. Five playable games, each adapting to the current
estimate, with the recommendation pinned to the top of the list and highlighted
in place.

## History

Filter by 7 / 30 / 90 days. A summary row (check-ins, average level, calmest,
how many had a game), then three trend charts — stress level, heart rate and
RMSSD — drawn with `CustomPaint`. Below, one card per session showing date,
time, level, HR, RMSSD, duration and the game played.

Tapping a card opens the full record: level, all four features, mean R-R,
confidence, game and score, before/after levels, data source, engine version
and the raw timestamp.

Empty states are friendly and offer the action that fixes them.

## Profile

Avatar, name, email, age. Four statistics: total check-ins, games played,
calming sessions, current streak. The baseline block showing baseline, current
and difference per feature. A system block reporting Device (`Not connected`),
Data source (`Demo Mode`) and Model (`Demo Stress Engine (demo-1.0.0)`).
Log out with confirmation.

## Baseline

"Set my calm baseline" records a 20-second capture and stores HR, RMSSD, SDNN
and pNN50 as a reference. It is used for context only and does not affect the
estimate — stated on screen and in Profile.

## Settings

- **Appearance** — Light / Dark / System, and Reduce motion.
- **Measurement** — Demo mode, measurement duration.
- **Feedback** — Sound, haptics.
- **Data** — Export as JSON to the clipboard, reset baseline, clear local
  history (with confirmation).
- **Developer** — the demo panel.
- **About** — about, privacy and disclaimer.
- Log out.

## Developer / demo panel

Labelled **DEVELOPER / DEMO MODE** at the top. Select level 1–5 and the whole
app follows. Generate a demo measurement, seed 60 days of history, view the
current dummy feature vector with its arousal score and predicted level, test
the recommended game, reset the baseline, clear history.

## Accessibility

- Every stress level carries a number, a written label and an icon, so meaning
  never depends on colour. Focus Blocks and Calm Catch use shape as well as
  colour to distinguish elements.
- Touch targets are at least 44–56 px; buttons have explicit minimum sizes.
- Semantic labels on the gauge, metric tiles, game cards, HUD values and the
  garden palette, including lock state.
- Reduce motion is honoured from both the OS setting and the in-app switch.
- Text uses the theme scale and reflows; long values ellipsize rather than
  overflow.

## Responsive design

Content is centred with a max width of 560 px so it stays comfortable on large
phones. Game worlds use fractional coordinates rather than pixels. HRV values
use a width-derived two-column wrap rather than a fixed grid. Rows that could
overflow on a narrow screen use `Wrap` so items reflow onto a second line.
Widget tests run at 420×900.

## Honesty rules

- Simulated values are labelled "Demo data" or "Demo / simulated data".
- The app says "estimated stress level", never "your stress is".
- The post-game level is described as simulated, and the screen says the value
  will come from a fresh measurement once the sensor is connected.
- No fake accuracy figures, and no placeholder model file.
- The disclaimer appears in About and Settings, with one quiet line on Home —
  present, not shouted.
