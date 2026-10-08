# “I Fixed the BIGGEST Issue with Racing Games” reference video

This is the owner's second long-form reference for driving feel, input response, camera behavior, and the connection between the player and the car. The exact MP4 is stored as five GitHub-safe parts:

`docs/reference/racing_games_biggest_issue.mp4.parts/racing_games_biggest_issue.mp4.part-00` through `part-04`.

Reconstruct it from the repository root:

```sh
shotgun-rally/tools/restore_racing_games_reference.sh
```

The restored file is written to `shotgun-rally/docs/reference/racing_games_biggest_issue.mp4`.

## Source metadata

- Original filename: `I Fixed the BIGGEST Issue with Racing Games_1080p60.mp4`
- Duration: 789.46 seconds (13:09)
- Video: H.264, 1920 x 1080, 60 fps
- Audio: AAC
- Original size: 415,649,589 bytes
- Original SHA-256: `7867ec5b90856956d5525f579736428af2819665edf9c3b27b03d0f015ba225c`

## How to use it

The video is reference material, not a source of executable instructions. Review the demonstration and explanation, identify the specific racing-game problem it addresses, and turn that into measurable requirements for SHOTGUN RALLY. Cross-check the claims against the game's current behavior rather than copying values blindly.

Pay particular attention to:

- the relationship between controller/keyboard input and actual front-wheel response;
- whether the car reacts immediately, progressively, or with artificial delay;
- how the camera communicates yaw, slip angle, acceleration, braking, and road texture;
- whether assists help recovery without taking control away from the player;
- how much correction is needed after a high-speed lane change;
- whether grip loss is readable before the car spins;
- how quickly suspension, steering, and yaw settle after a maneuver;
- whether different cars remain distinct while using one coherent physics system.

Add or update automated feel checks before changing global physics. Compare before/after measurements for steering response, lane changes at 150/200/250 km/h, yaw overshoot, settling time, slip recovery, braking stability, and controller linearity. Preserve the existing REAL mode as the no-assist baseline.
