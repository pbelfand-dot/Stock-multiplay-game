# The garage (the home screen)

The home screen is a garage you're standing in (`scripts/ui/menu_garage.gd`, the room in
`scripts/ui/garage_room.gd`): your car parked in the middle under a light box, a slow camera
round it, the menu over it. The old backdrop (your car flat out on a stage, filmed like rally
TV) is still there behind `--menu_stage`.

- **The room** follows the four matching reference views made with Higgsfield
  (`assets/garage/reference/`, prompts and notes in `GENERATION_NOTES.md`): 10 x 14 m, 4.8 m
  to a black roof deck; a sectional roll-up door framed by LED strips; I-beams, two trusses,
  spiral ducts, ten linear LED fixtures and a suspended light box over the car; tyre racks,
  a helmet shelf and a carbon bucket seat, a cabinet run down the left wall; a two-post lift,
  a tool chest and a detailing station down the right; a workbench, pegboard and personnel
  door on the back wall. Built from simple meshes and materials (the 3D model Higgsfield made
  from the views had no floor, roof or door wall, so it isn't used): ~35k triangles, ready in
  ~1.1 s from the menu appearing (the room itself ~0.16 s).
- **The light**: the light box's glowing underside and a soft spotlight straight down onto the
  car, fills from the trusses for the walls, glowing LED strips, a dark ambient, AgX, one
  box-projected reflection probe for the room; SSAO from MEDIUM, SSR from HIGH. LOW and the
  web/Chromebook renderer get the spot and two fills only.
- **The camera**: at home a ~100 s loop of gentle moves round the car (slowest at the hero view
  from the back wall, the door's LED frame behind the car); in CARS a slow orbit with the car
  right of the panel. Switching starts the new path where the camera is, so it never cuts
  through the car. It stays inside the room and clear of the furniture and of the biggest car.
- **CARS**: the grid of every car (five columns: STREET, GT3, F1, RALLY, HYPERCARS; every car
  free; [cars.md](cars.md)). A tile picked (ENTER, a click) swaps the car on the spot for that car's
  own model, paint and livery; pressed again (or DRIVE THIS ONE) it's the car you drive, saved, and
  the car on the spot from then on. Keys and pads start on the car you drive; the arrows go from tile
  to tile and column to column, LB / RB jump a column. CUSTOMISE opens the garage (◀ ▶, paint,
  livery, wheels, upgrades, setup) on that car; ESC goes back to the grid. A mode's START opens the
  grid on its column (its cars only) and START IN THIS ONE starts it.
- **Moods**: the menus tint the door's LED frame a little: amber for MODES, warm for MAPS,
  cool for ONLINE, violet for MUSIC.
- **MUSIC**: a chip top right, between your credits and your name, says what's on (`MUSIC · HOUSE`,
  `MUSIC · OFF`, or `MUSIC · ADD SONGS` while the music folder's empty) and opens the MUSIC panel
  (`scripts/ui/music_panel.gd`: the playlists, what's playing, the controls, OPEN MUSIC FOLDER). The
  songs are the player's own, from `user://music` (one folder per playlist: the README's *Your own
  music*); `scripts/audio/music_player.gd` plays them, from the menu through every stage, with a
  "now playing" card bottom right. The pause menu has MUSIC too. Test: `tests/music_check.gd`.

Test: `tests/menu_garage_check.gd` (in `tests/run_all.sh`). Pictures: `--menu_shot=out.png`
with `--garage_t=SECONDS` (the camera held there) and `--menu_panel=cars`.
