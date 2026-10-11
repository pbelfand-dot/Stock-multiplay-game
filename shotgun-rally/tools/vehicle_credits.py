"""The cars' credits: where each model came from, its author and licence, and
anything to settle before the game goes anywhere public, from the registry
(data/vehicles/*.json: "source", "limitations").

  python3 tools/vehicle_credits.py > docs/CREDITS.md
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def cell(s):
    return str(s).replace("|", "/").replace("\n", " ").strip()


def main():
    rows = []
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "vehicles", "*.json"))):
        e = json.load(open(f))
        s = e.get("source", {})
        real = e.get("real", {})
        car = " ".join(str(real.get(k, "")) for k in ("manufacturer", "model")).strip() or "-"
        flags = [l for l in e.get("limitations", []) if "rovenance" in l or "no-AI" in l or "Not looked at" in l]
        if "no AI" in json.dumps(s) or "no-AI" in json.dumps(s):
            flags.append("no-AI licence or handling: converted and checked by local scripts only")
        rows.append((e.get("order", 999), e["name"], e["id"], car, s.get("package", "-"), s.get("author", ""),
                     s.get("license", ""), s.get("url", ""), "; ".join(dict.fromkeys(flags))))
    rows.sort()
    print("# Credits: the cars\n")
    print("Generated from the vehicle registry by `tools/vehicle_credits.py` (don't edit by hand).")
    print("SHOTGUN RALLY is a game for friends: several models below are game rips or carry")
    print("non-commercial licences. **Before any public or paid release**, every row with a")
    print("provenance note or a NonCommercial / unconfirmed licence must be replaced or cleared, and")
    print("the real makes' names and badges (in the registry's `real` and in some textures) settled.")
    print("Licence texts and attribution files from the packages are kept with the restored packages")
    print("(`assets/cars_restored/`, outside the build); the inventory, with each candidate's evidence,")
    print("is `docs/VEHICLE_PROGRESS.md`.\n")
    print("| In game | Real car | Source | Author | Licence | Notes |")
    print("|---|---|---|---|---|---|")
    for _, name, vid, car, pkg, author, lic, url, flags in rows:
        src = "[%s](%s)" % (cell(pkg), url) if url else cell(pkg)
        print("| %s (`%s`) | %s | %s | %s | %s | %s |" % (cell(name), vid, cell(car), src, cell(author) or ("the owner" if lic == "the owner's" else "see VEHICLE_PROGRESS"),
                                                      cell(lic) or "see VEHICLE_PROGRESS", cell(flags)))
    print("\n## Everything else\n")
    print("- Engine sounds: markeasting/engine-audio (MIT code; its recordings: see `tools/engine_sound/README.md`);")
    print("  the electric car's motor, turbo whistles, blow-off and supercharger whine are made in code.")
    print("- The game's own cars (KESTREL, COMET, VORTEX, MARTELLO), the crew's seats and the loading art: Higgsfield,")
    print("  from the owner's account. The crew: the owner's Claude Racer character (Mixamo-rigged).")
    print("- Co-driver voice: Higgsfield Seed Audio 1.0, preset voice \"Fraser\". Font: Oswald (SIL OFL).")
    print("- The driver's gloves (`assets/models/gloves/gloves.glb`): Higgsfield, from the owner's account: a photo")
    print("  made with GPT Image 2.5 (a red and white racing glove gripping a bar), made 3D with Tripo H3.1, fitted")
    print("  to the steering wheel rim by `tools/fit_glove.py` (Blender).")
    print("- Wheels (`assets/wheels/`, `tools/import_wheels.py`; all CC0): the 17 in five-spoke and 225/45 R17 tyre")
    print("  from the [Innerscene Parts Library](https://www.innerscene.com/tools/library/3d-parts/17-inch-five-spoke-alloy-wheel-and-tyre-x3d-50c20c60);")
    print("  the CC96 rims by [IceMaan](https://icemaan.itch.io/free-low-poly-car3-3-body-kits-4-rims); the wheels of the")
    print("  [USD Working Group's USD_Mini_Car_Kit](https://github.com/usd-wg/assets/tree/3b75c2dad6a494897557dcca0098257bcf42a8c6/full_assets/Vehicles/USD_Mini_Car_Kit).")
    print("  The garage's other wheel types are built in code (`scripts/vehicle/wheel_gen.gd`), their names made up.")


if __name__ == "__main__":
    main()
