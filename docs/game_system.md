# Game system

Five real, playable mini-games. No placeholders, no game engine — each is plain
Flutter using `Ticker`, `AnimationController` and `CustomPaint`.

## Architecture

```
GameCatalog          static definitions: name, icon, duration, levels
      │
GameRecommendationService   level -> which game to suggest
      │
GameLauncher         maps a game id to its screen, runs it, records the result
      │
      ├── the game screen pops a GameResult
      │
GameSessionManager   GameResult -> GameSession, simulates the post level
      │
GameSessionRepository  persists it
      │
GameResultScreen     shows the before/after comparison
```

A game screen knows nothing about persistence, stress levels or the
biofeedback loop. It plays, then pops a `GameResult`:

```dart
class GameResult {
  final String gameId;
  final Duration duration;
  final int score;
  final double completion;        // 0..1
  final Map<String, num> metrics; // game-specific extras
}
```

`GameLauncher.play()` does the rest: records the session, links it to the
originating check-in when there is one, and pushes the result screen.

## The five games

| Game | Id | Mechanic | Adapts to level | Calming |
| --- | --- | --- | --- | --- |
| Calm Breathing | `calm_breathing` | Paced breathing circle | Session length | yes |
| Pulse Runner | `pulse_runner` | Endless runner, tap to hop | Speed, obstacle spacing | no |
| Zen Garden | `zen_garden` | Place objects on a canvas | — (open-ended) | yes |
| Focus Blocks | `focus_blocks` | Memory sequence on a 3×3 grid | Sequence length, flash speed | no |
| Calm Catch | `calm_catch` | Catch falling objects | Fall speed, distractions | no |

### 1. Calm Breathing — the primary biofeedback activity

A circle expands on the inhale and contracts on the exhale, with a short hold
between. The rhythm is **4 s in, 0.7 s hold, 6 s out** — a longer exhale than
inhale is the conventional pacing for downregulation.

Session length adapts to the current estimate, because a longer reset is most
useful when the reading is highest:

| Level | Session |
| --- | --- |
| 1–2 | 90 s |
| 3 | 120 s |
| 4 | 150 s |
| 5 | 180 s |

Shows the phase label, breath count, elapsed and remaining time, and a progress
bar. Pause, Resume and End are all available. A gentle haptic marks each
completed breath. Score is `breaths × 10` — a calm activity is scored on
breaths completed, never on speed.

### 2. Pulse Runner

The player hops over obstacles and collects orbs while the ground scrolls.
World coordinates are fractions of the play area, so it is resolution
independent and cannot overflow on a small phone.

Higher estimate → slower speed and wider spacing:

| Level | Speed | Spawn interval |
| --- | --- | --- |
| 1 | 0.62 | 0.72 s |
| 3 | 0.48 | 0.95 s |
| 5 | 0.34 | 1.35 s |

Hitting an obstacle costs a little momentum and nothing else. There is no
game over and no penalty for a high reading.

### 3. Zen Garden

An open canvas. Tap to place a stone, flower, water ripple, grass or lantern;
long-press to remove the nearest object; undo and clear are available. Objects
are stored as 0..1 fractions, so a garden survives rotation and different
screen sizes, and it persists between sessions in `LocalStore`.

Grass unlocks after 2 completed sessions and the lantern after 5. Locked items
show a padlock and a tooltip explaining how to unlock them.

There is nothing to win. Completion is measured as placements this session
against a target of six.

### 4. Focus Blocks

A 3×3 grid flashes a sequence; the player repeats it. Sequences lengthen every
two rounds. Three mistakes end the run, and a mistake replays the same sequence
rather than ending the round outright.

| Level | Starting length | Flash on |
| --- | --- | --- |
| 1–2 | 4 | 420 ms |
| 3 | 3 | 520 ms |
| 4–5 | 2 | 640 ms |

A lit block changes size and shows a dot as well as changing colour, so the
sequence is readable without relying on colour perception.

Tracks score, round, accuracy and elapsed time.

### 5. Calm Catch

Drag a basket to catch stars, leaves and droplets. Distractions are hollow
squares — a different shape as well as a duller colour. Catching one costs a
few points but the score never goes negative and the round never ends early.

| Level | Fall speed | Distraction chance |
| --- | --- | --- |
| 1 | 0.46 | 26% |
| 3 | 0.34 | 18% |
| 5 | 0.22 | 5% |

Tracks score, items caught, accuracy and time remaining.

## Recommendation mapping

Owned by `StressLevelConfig` and resolved by `GameRecommendationService`. The
first id is the primary suggestion behind the big "PLAY NOW" button.

| Level | Primary | Also offered |
| --- | --- | --- |
| 1 Very Low | Zen Garden | Calm Catch, Pulse Runner |
| 2 Low | Zen Garden | Calm Catch, Pulse Runner |
| 3 Moderate | Calm Breathing | Focus Blocks, Calm Catch |
| 4 High | Calm Breathing | Zen Garden, Calm Catch |
| 5 Very High | Calm Breathing | Zen Garden |

Levels 3–5 always lead with a calming activity — asserted by
`game_recommendation_test.dart`. The recommendation appears on Home, on the
stress result screen, and pinned at the top of the Games screen.

## Shared chrome

`GameScaffold` gives every game the same title bar, HUD strip, pause overlay
and "End this session?" confirmation, so the five games stay consistent without
sharing any gameplay code. Ending early still records the session — progress so
far is never thrown away.

## The biofeedback loop

```
Check-in ─▶ Level ─▶ Recommended game ─▶ Play ─▶ GameResult
                                                     │
                                          GameSessionManager
                                                     │
                                          Before / after comparison
                                                     │
                                                  History
```

`GameSessionManager.simulatePostLevel` is the **only** place the post-session
estimate is produced:

- Completion below 75% → the estimate is unchanged.
- Completion at or above 75% → down one level.
- A calming game completed in full from level 4 or 5 → down two levels.
- Never below level 1.

This is a demo rule so the loop can be demonstrated before re-measurement is
possible. The result screen says so in as many words, and describes a change in
the estimate rather than claiming the game treated anything. When the hardware
lands, the honest version is to re-measure and run the engine again — one
method changes.
