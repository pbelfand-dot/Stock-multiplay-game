extends Resource
## A surface the tyres can be on (asphalt, gravel, snow, ice, mud, grass...):
## how it changes the car's tyre. The tyre's own figures (TireConfig) are for
## its reference surface, loose gravel; a surface scales them:
##   * grip: the friction coefficient, both ways (snow ~0.45 of gravel's, ice ~0.15)
##   * where the grip peaks: on a loose surface the tyre ploughs and digs, so it
##     builds its grip over more slip (a bigger slip angle, a higher slip ratio)
##     and has less cornering stiffness; on asphalt it bites early
##   * how much grip a sliding tyre keeps: on gravel, snow and mud a sliding or
##     locked tyre pushes a wedge of the surface up and keeps most of it; on
##     asphalt, grass and ice it skates and loses more
##   * rolling resistance: soft ground sinks under the tyre and drags
## Each StaticBody3D the tyres touch says what it is with its meta "surface": a
## name (surfaces.gd looks it up in data/surfaces/<name>.tres) or one of these.
## Edit them in the inspector.

## What it's called (the telemetry shows it).
@export var display_name := "gravel"
## The tyre's grip on it, as a share of its grip on loose gravel.
@export_range(0.02, 2.0, 0.01) var grip := 1.0
## Where the grip peaks (slip angle and slip ratio), x the tyre's own (on gravel).
@export_range(0.2, 3.0, 0.01) var peak_scale := 1.0
## How much grip a sliding / locked / spinning tyre keeps, x what it keeps on gravel.
@export_range(0.3, 1.5, 0.01) var slide_grip := 1.0
## Rolling resistance, x the tyre's own (on gravel).
@export_range(0.0, 10.0, 0.05) var rolling_scale := 1.0
