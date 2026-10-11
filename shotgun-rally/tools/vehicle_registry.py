#!/usr/bin/env python3
"""The vehicle registry's tool: data/vehicles/<id>.json, one file per vehicle (the
game reads them: scripts/game/vehicle_registry.gd).

    python3 tools/vehicle_registry.py fmt      # rewrite every entry in the compact layout
    python3 tools/vehicle_registry.py check    # check every entry (exit 1 on a problem)
    python3 tools/vehicle_registry.py table    # a markdown table of them all

An entry (only "id", "name" and "order" are required; see docs/vehicles.md):
  id, name (the garage's), order (the garage's order), model (assets/models/cars/<model>/;
  "" = the shared Higgsfield body), category, role, real {manufacturer, model, year, trim,
  race_class}, specs {power_hp, weight_kg, drivetrain, transmission, wheelbase_mm,
  top_speed_kmh, front_weight}, garage {price, engine_sound, livery, number, colours, wheels,
  power, grip, brakes, drive_front, blurb, mass} (absent: not in the garage), traffic
  {weight, paints} (absent: never traffic), physics (CarSpecs: see car_specs.gd), interior
  {own, camera, notes}, driver_seat {overrides}, source {package, file, author, license,
  url, attribution}, research [urls], limitations [text], checks {zero_100_max: s, the
  tests' limit on gravel}
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = os.path.join(os.path.dirname(HERE), "data", "vehicles")
ROLES = {"rally", "touge_grip", "drift", "player_road", "track", "formula", "hypercar", "race_prototype",
         "traffic", "premium_traffic", "special"}
CATEGORIES = {"rally", "jdm", "euro", "american", "hyper", "race", "traffic"}
ORDER = ["id", "name", "order", "model", "category", "role", "real", "specs", "garage", "traffic",
         "physics", "checks", "interior", "driver_seat", "source", "research", "limitations"]


def _scalar(v):
    return json.dumps(v, ensure_ascii=False)


def _inline(v):
    """Lists of numbers / short lists on one line."""
    if isinstance(v, list):
        return "[" + ", ".join(_inline(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join("%s: %s" % (_scalar(k), _inline(x)) for k, x in v.items()) + "}"
    return _scalar(v)


def _flat(v):
    return isinstance(v, list) and all(not isinstance(x, dict) for x in v) and len(_inline(v)) < 140


def dump(e):
    keys = [k for k in ORDER if k in e] + sorted(k for k in e if k not in ORDER)
    lines = ["{"]
    for i, k in enumerate(keys):
        v = e[k]
        end = "," if i < len(keys) - 1 else ""
        if isinstance(v, dict) and v:
            lines.append("\t%s: {" % _scalar(k))
            sub = list(v.items())
            for j, (sk, sv) in enumerate(sub):
                send = "," if j < len(sub) - 1 else ""
                if isinstance(sv, (dict, list)) and not _flat(sv) and not (isinstance(sv, dict) and len(_inline(sv)) < 140):
                    body = json.dumps(sv, ensure_ascii=False, indent="\t")
                    body = body.replace("\n", "\n\t\t")
                    lines.append("\t\t%s: %s%s" % (_scalar(sk), body, send))
                else:
                    lines.append("\t\t%s: %s%s" % (_scalar(sk), _inline(sv), send))
            lines.append("\t}" + end)
        elif isinstance(v, list) and not _flat(v):
            lines.append("\t%s: [" % _scalar(k))
            for j, x in enumerate(v):
                lines.append("\t\t%s%s" % (_inline(x), "," if j < len(v) - 1 else ""))
            lines.append("\t]" + end)
        else:
            lines.append("\t%s: %s%s" % (_scalar(k), _inline(v), end))
    lines.append("}")
    return "\n".join(lines) + "\n"


def entries():
    out = []
    for f in sorted(os.listdir(DIR)):
        if f.endswith(".json"):
            with open(os.path.join(DIR, f), encoding="utf-8") as fh:
                out.append((f, json.load(fh)))
    return out


def check():
    bad = 0
    ids = set()
    models = os.path.join(os.path.dirname(HERE), "assets", "models", "cars")
    for f, e in entries():
        def fail(msg):
            nonlocal bad
            bad += 1
            print("%s: %s" % (f, msg))
        for k in ("id", "name", "order"):
            if k not in e:
                fail("no %s" % k)
        if e.get("id") + ".json" != f:
            fail("the file isn't named after its id")
        if e.get("id") in ids:
            fail("a duplicate id")
        ids.add(e.get("id"))
        if e.get("role") and e["role"] not in ROLES:
            fail("unknown role %s" % e["role"])
        if e.get("category") and e["category"] not in CATEGORIES:
            fail("unknown category %s" % e["category"])
        m = e.get("model", "")
        if m and not os.path.exists(os.path.join(models, m, m + ".glb")):
            fail("no model assets/models/cars/%s/%s.glb" % (m, m))
        if m and "physics" not in e:
            fail("a model of its own but no physics")
        if "traffic" in e and e.get("role") in ("race_prototype", "track", "hypercar"):
            fail("a %s can't be traffic" % e["role"])
        g = e.get("garage")
        if g is not None:
            for k in ("price", "engine_sound", "livery", "number", "colours", "wheels", "power", "grip", "brakes", "drive_front", "blurb"):
                if k not in g:
                    fail("garage: no %s" % k)
    print("%d entries, %d problem(s)" % (len(ids), bad))
    return bad


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "fmt":
        for f, e in entries():
            with open(os.path.join(DIR, f), "w", encoding="utf-8") as fh:
                fh.write(dump(e))
        print("formatted")
    elif cmd == "check":
        sys.exit(1 if check() else 0)
    elif cmd == "table":
        print("| id | name | real car | role | hp | kg | drive | garage | traffic |")
        print("|---|---|---|---|---|---|---|---|---|")
        for f, e in sorted(entries(), key=lambda x: x[1].get("order", 0)):
            r, s = e.get("real") or {}, e.get("specs") or {}
            real = " ".join(str(x) for x in (r.get("year"), r.get("manufacturer"), r.get("model"), r.get("trim")) if x)
            print("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (e["id"], e["name"], real or "fictional",
                e.get("role", ""), s.get("power_hp", ""), s.get("weight_kg", ""), s.get("drivetrain", ""),
                "yes" if "garage" in e else "", "yes" if "traffic" in e else ""))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
