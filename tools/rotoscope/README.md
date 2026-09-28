# Rotoscoping emotes from a phone video

How the dance emote (`assets/anims/dance.json`) was made from a clip of a real dance.

1. Track the body on every frame (MediaPipe pose, 33 landmarks in metres):

       python3 -m venv mpenv && mpenv/bin/pip install mediapipe opencv-python-headless
       curl -LO https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task
       mpenv/bin/python track.py clip.mov track.json pose_landmarker_heavy.task

   (Linux needs `libegl1 libgles2`.)

2. Fit the rig's joint angles and bake 15 fps keyframes:

       python3 convert.py track.json ../../assets/anims/<name>.json 11.0

   The last argument is where to cut the clip, in seconds. The tail blends back into
   frame 0 so the emote loops. The arm solver prefers reaching forward over swinging
   out to the side. It also corrects what a phone camera can't see: forearms pointed at
   the lens, the far arm hidden side-on, and hips sitting back on the punches.

3. Check it against the video: `godot --path . -- --dancecheck=/tmp/out --times=1.2,4.8`
   renders the rig at those times. Put the frames next to the same video frames.

Hook a new clip up as an emote by adding a `"<name>"` case that calls `_apply_clip`
in `scripts/art/character.gd`, then add it to `EMOTES` in `scripts/player/player.gd`
and give it a key in `config.gd`.
