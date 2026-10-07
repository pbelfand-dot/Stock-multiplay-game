#!/usr/bin/env python3
"""A registry entry's physics block (CarSpecs: see car_specs.gd) from a car's researched
numbers, so every car is worked out the same way:

    from vehicle_physics import physics
    p = physics(hp=717, hp_rpm=6000, nm=889, nm_rpm=4800, kg=2029, front=0.57, drive="rwd",
                gears=[4.71, ...], final=2.62, engine="sc", chassis="sport", cd=0.398, area=2.35)

  * the torque curve: by the engine's kind ("na", "na_high" (a high-revving race or
    sports engine), "turbo", "sc", "ev", "hybrid"), peaking at nm_rpm, and scaled so its
    power peaks at hp at hp_rpm (the curve's most torque x revs is the rated power)
  * no published torque (race cars): from the power, as the kind of engine makes it
  * limiter: given, or a little past the power peak; idle by kind
  * no published gears: a spread for the number of gears (closer for race boxes), the
    top gear and final drive set so the limiter in top is the top speed (+5 %)
  * diffs by drive: rear-drive an LSD at the back; front-drive open (an LSD for "lsd"
    in front_diff); four-wheel drive a centre diff at its split, LSDs front and rear
  * aero by chassis when not given: drag, frontal area, downforce (x the rally car's
    way of working it out: car_specs.gd)
"""
import math

KW_PER_HP = 0.7457
IDLE = {"na": 850.0, "na_high": 1000.0, "turbo": 850.0, "sc": 750.0, "ev": 500.0, "hybrid": 1000.0}
SPREAD = {4: 2.9, 5: 4.0, 6: 4.6, 7: 5.6, 8: 7.0, 9: 7.5, 10: 8.0}
AERO = {  # cd, area m2, down
    "rally": (0.40, 2.0, 0.3), "road": (0.32, 2.2, 0.0), "suv": (0.36, 2.9, 0.0), "sport": (0.33, 2.1, 0.1),
    "track": (0.45, 1.95, 2.4), "prototype": (0.50, 1.75, 3.8),
}
BRAKE = {"rally": 1.0, "road": 0.85, "suv": 0.85, "sport": 1.0, "track": 1.25, "prototype": 1.4}


def _curve_shape(kind, nm_rpm, hp_rpm, limiter):
    """[rpm, x the peak] points before the power fix."""
    pts = []
    if kind == "ev":
        # flat torque to the base speed, then constant power (torque ~ 1/rpm)
        for r in (500, nm_rpm * 0.5, nm_rpm, nm_rpm * 1.5, nm_rpm * 2.0, nm_rpm * 2.6, limiter):
            pts.append([r, 1.0 if r <= nm_rpm else nm_rpm / r])
        return pts
    lo = {"na": 0.62, "na_high": 0.5, "turbo": 0.38, "sc": 0.55, "hybrid": 0.75}[kind]
    flat = {"na": 0.0, "na_high": 0.0, "turbo": 0.35, "sc": 0.25, "hybrid": 0.4}[kind]   # (the share of the way to the power peak it stays at the top)
    r0 = 1000.0
    steps = [r0, r0 + (nm_rpm - r0) * 0.35, r0 + (nm_rpm - r0) * 0.7, nm_rpm]
    vals = [lo, lo + (1 - lo) * 0.55, lo + (1 - lo) * 0.88, 1.0]
    for r, v in zip(steps, vals):
        pts.append([r, v])
    top = nm_rpm + (hp_rpm - nm_rpm) * flat
    if top > nm_rpm + 50:
        pts.append([top, 1.0])
    pts.append([hp_rpm, None])      # (set by the power fix)
    pts.append([limiter, None])
    return pts


def physics(hp, hp_rpm, kg, drive, nm=None, nm_rpm=None, front=None, gears=None, final=None, engine="na",
            chassis="road", limiter=None, top_kmh=None, tyre_radius=0.33, cd=None, area=None, down=None,
            brake=None, turbo_spool=None, front_share=None, centre="lsd", front_diff=None, n_gears=6):
    kind = engine
    if limiter is None:
        limiter = hp_rpm * (1.0 if kind == "ev" else 1.07)
    if kind == "ev":
        # the motor's base speed: full torque up to it, full power from it (power = torque x rpm)
        nm_rpm = hp * KW_PER_HP * 9549.3 / nm if nm else hp_rpm
    if nm_rpm is None:
        nm_rpm = {"na": 0.72, "na_high": 0.78, "turbo": 0.45, "sc": 0.75, "ev": 0.25, "hybrid": 0.55}[kind] * hp_rpm
    p_kw = hp * KW_PER_HP
    if nm is None:
        # torque from power: what this kind of engine has at its power peak (x the peak torque)
        at_peak = {"na": 0.88, "na_high": 0.9, "turbo": 0.8, "sc": 0.92, "ev": 0.3, "hybrid": 0.8}[kind]
        nm = p_kw * 9549.3 / (hp_rpm * at_peak)
    pts = _curve_shape(kind, nm_rpm, hp_rpm, limiter)
    if kind != "ev":
        need = min(p_kw * 9549.3 / (nm * hp_rpm), 1.0)          # the curve at the power peak
        for p in pts:
            if p[0] == hp_rpm:
                p[1] = need
        # past the power peak: falling a little faster than the power peak's torque
        pts[-1][1] = need * (0.9 if kind in ("na_high", "hybrid") else 0.86) * hp_rpm / limiter * (limiter / hp_rpm) ** 0.4
        # no point above the power peak's value after it (the power peaks where it's rated)
    else:
        nm = p_kw * 9549.3 / nm_rpm
    pts = [[round(r), round(min(v, 1.0), 3)] for r, v in pts if v is not None]
    pts = sorted({r: v for r, v in pts}.items())
    curve = [[r, v] for r, v in pts]
    # check: the curve's power peak is the rated power (within 2 %)
    best = max(nm * v * r / 9549.3 for r, v in curve)
    if abs(best - p_kw) / p_kw > 0.02:
        # (a point before the peak can top it on a short curve: scale the torque so the peak is right)
        nm *= p_kw / best
    out = {"chassis": chassis, "mass": float(kg), "front": float(front if front else {"rwd": 0.53, "fwd": 0.61, "awd": 0.56}[drive]),
           "torque": round(float(nm), 1), "curve": curve, "idle": IDLE[kind], "limiter": float(round(limiter)),
           "turbo": 0.0}
    if kind in ("turbo", "hybrid") and kind != "ev":
        a, b = turbo_spool or ((1800.0, 3200.0) if kind == "turbo" else (1500.0, 2600.0))
        out.update({"turbo": 0.4 if kind == "turbo" else 0.25, "spool": [a, b], "spool_time": 0.35, "anti_lag": False})
    if not gears:
        n = 1 if kind == "ev" else n_gears
        if n == 1:
            gears = [1.0]
        else:
            spread = SPREAD.get(n, 4.6) * (0.65 if chassis in ("track", "prototype") else 1.0)
            ratio = spread ** (1.0 / (n - 1))
            top = 0.8 if n >= 6 else 1.0
            gears = [round(top * ratio ** (n - 1 - i), 3) for i in range(n)]
        if final is None:
            v = (top_kmh or 250.0) * 1.05 / 3.6
            final = round(limiter * 2 * math.pi / 60.0 * tyre_radius / (v * gears[-1]), 2)
    out.update({"gears": gears, "final": float(final), "drive": drive})
    if drive == "rwd":
        out["rear"] = ["lsd", 0.35, 0.15, 30.0]
    elif drive == "fwd":
        out["front_diff"] = front_diff or ["open", 0.0, 0.0, 0.0]
    else:
        out["front_share"] = front_share if front_share is not None else 0.4
        out["centre"] = [centre, 0.25, 0.2, 30.0] if centre != "locked" else ["locked", 0.0, 0.0, 0.0]
        out["front_diff"] = front_diff or ["lsd", 0.2, 0.1, 20.0]
        out["rear"] = ["lsd", 0.35, 0.15, 30.0]
    c0, a0, d0 = AERO[chassis]
    out.update({"cd": cd if cd else c0, "area": area if area else a0, "down": down if down is not None else d0,
                "brake": brake if brake else BRAKE[chassis]})
    return out


def power_kw(p):
    return max(p["torque"] * v * r / 9549.3 for r, v in p["curve"])


if __name__ == "__main__":
    import json
    p = physics(hp=717, hp_rpm=6000, nm=889, nm_rpm=4800, kg=2029, front=0.57, drive="rwd",
                gears=[4.71, 3.14, 2.1, 1.67, 1.29, 1.0, 0.84, 0.67], final=2.62, engine="sc", chassis="sport",
                cd=0.398, area=2.35, limiter=6300)
    print(json.dumps(p))
    print("power %.0f hp" % (power_kw(p) / KW_PER_HP))
