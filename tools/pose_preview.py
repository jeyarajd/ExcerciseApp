"""Render stick-figure previews of every exercise in FloorAge/Resources/exercises.json.

Uses the same skeleton, Euler order (R = Rx @ Rz @ Ry), ground solver and keyframe
blending as the app's PoseAnimator, so poses can be tuned without a Mac.

    python tools/pose_preview.py            # all exercises -> tools/out/<id>.png
    python tools/pose_preview.py squat      # one exercise
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "FloorAge", "Resources", "exercises.json")
OUT = os.path.join(ROOT, "tools", "out")

TOE_Z = 0.15  # toe z with pelvis at the origin in the standing pose
SCALE = 150  # pixels per metre
PANEL_W, PANEL_H = 230, 320


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def local_rot(e):
    x, y, z = (math.radians(v) for v in e)
    return rx(x) @ rz(z) @ ry(y)


def fk(rig, angles, pelvis_pos):
    world = {}
    for j in rig["joints"]:
        r_local = local_rot(angles.get(j["name"], [0, 0, 0]))
        offset = np.array(j["offset"], dtype=float)
        if j["parent"] is None:
            world[j["name"]] = (r_local, pelvis_pos + offset)
        else:
            r_p, p_p = world[j["parent"]]
            world[j["name"]] = (r_p @ r_local, p_p + r_p @ offset)
    return world


def contact_points(rig, world):
    pts = {}
    for name, c in rig["contacts"].items():
        r, p = world[c["joint"]]
        pts[name] = p + r @ np.array(c["offset"], dtype=float)
    return pts


def solve_pelvis(rig, angles, kf):
    """Pelvis position that puts this keyframe's ground contact on the floor."""
    pts = contact_points(rig, fk(rig, angles, np.zeros(3)))
    mode = kf.get("ground", "feet")
    hip_x = next(j["offset"][0] for j in rig["joints"] if j["name"] == "lHip")
    if mode == "feet":
        anchor = (pts["lToe"] + pts["rToe"]) / 2
        target_x, target_z = 0.0, TOE_Z
        y_min = min(pts[k][1] for k in ("lHeel", "lToe", "rHeel", "rToe"))
    elif mode in ("left", "right"):
        side = "l" if mode == "left" else "r"
        anchor = pts[side + "Toe"]
        target_x, target_z = (hip_x if side == "l" else -hip_x), TOE_Z
        y_min = min(pts[side + "Heel"][1], pts[side + "Toe"][1])
    elif mode == "seat":
        anchor = pts["seat"]
        target_x, target_z = 0.0, kf.get("seatZ", 0.0)
        y_min = pts["seat"][1]
    else:  # lowest
        anchor = np.zeros(3)
        target_x, target_z = 0.0, kf.get("rootZ", 0.0)
        y_min = min(p[1] for p in pts.values())
    return np.array([target_x - anchor[0], -y_min, target_z - anchor[2]])


def resolve(data, kf):
    angles = {k: list(v) for k, v in data["poses"].get(kf.get("pose", ""), {}).items()}
    for k, v in kf.get("joints", {}).items():
        angles[k] = list(v)
    return angles


def smoothstep(u):
    return u * u * (3 - 2 * u)


def clamp_to_floor(rig, angles, pelvis):
    """Lift the body if blending between ground modes pushed any contact through the floor."""
    pts = contact_points(rig, fk(rig, angles, pelvis))
    low = min(p[1] for p in pts.values())
    if low < 0:
        pelvis = pelvis + np.array([0, -low, 0])
    return pelvis


def sample(data, ex, t):
    rig = data["rig"]
    kfs = ex["keyframes"]
    if t <= kfs[0]["t"]:
        a = resolve(data, kfs[0])
        return a, clamp_to_floor(rig, a, solve_pelvis(rig, a, kfs[0]))
    for ka, kb in zip(kfs, kfs[1:]):
        if ka["t"] <= t <= kb["t"]:
            u = smoothstep((t - ka["t"]) / max(kb["t"] - ka["t"], 1e-6))
            aa, ab = resolve(data, ka), resolve(data, kb)
            names = set(aa) | set(ab)
            ang = {n: [(1 - u) * x + u * y for x, y in zip(aa.get(n, [0, 0, 0]), ab.get(n, [0, 0, 0]))] for n in names}
            pa = solve_pelvis(rig, ang, ka)
            pb = solve_pelvis(rig, ang, kb)
            return ang, clamp_to_floor(rig, ang, (1 - u) * pa + u * pb)
    a = resolve(data, kfs[-1])
    return a, clamp_to_floor(rig, a, solve_pelvis(rig, a, kfs[-1]))


BONES = [
    ("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"),
    ("chest", "lShoulder"), ("lShoulder", "lElbow"), ("lElbow", "lWrist"),
    ("chest", "rShoulder"), ("rShoulder", "rElbow"), ("rElbow", "rWrist"),
    ("pelvis", "lHip"), ("lHip", "lKnee"), ("lKnee", "lAnkle"),
    ("pelvis", "rHip"), ("rHip", "rKnee"), ("rKnee", "rAnkle"),
]


def colour(name):
    if name.startswith("l"):
        return (40, 110, 230)
    if name.startswith("r"):
        return (220, 60, 50)
    return (30, 30, 30)


def draw_panel(img, ox, oy, world, pts, props, view, label):
    d = ImageDraw.Draw(img)
    ground_y = oy + PANEL_H - 30

    def proj(p):
        h = p[2] if view == "side" else p[0]
        return (ox + PANEL_W / 2 + h * SCALE, ground_y - p[1] * SCALE)

    d.line([(ox + 5, ground_y), (ox + PANEL_W - 5, ground_y)], fill=(150, 150, 150), width=2)
    for prop in props:
        if prop["type"] == "chair":
            x, y, z = prop["position"]
            h0 = z if view == "side" else x
            half = 0.21 if view == "side" else 0.22
            a = proj([h0 - half if view == "front" else 0, y, h0 - half])
            b = proj([h0 + half if view == "front" else 0, 0, h0 + half])
            d.rectangle([a[0], a[1], b[0], b[1]], outline=(160, 120, 60), width=2)
            if view == "side":
                back = proj([0, 0.9, h0 - half])
                d.line([a, back], fill=(160, 120, 60), width=3)
    # draw far side first so the near side is on top
    order = sorted(BONES, key=lambda b: 0 if b[1].startswith("r") else 1)
    for a, b in order:
        d.line([proj(world[a][1]), proj(world[b][1])], fill=colour(b), width=4)
    for side in ("l", "r"):
        d.line([proj(pts[side + "Heel"]), proj(pts[side + "Toe"])], fill=colour(side + "x"), width=4)
        d.line([proj(world[side + "Ankle"][1]), proj(pts[side + "Heel"])], fill=colour(side + "x"), width=2)
    head_r, head_p = world["head"]
    centre = proj(head_p + head_r @ np.array([0, 0.1, 0]))
    rad = 0.11 * SCALE
    d.ellipse([centre[0] - rad, centre[1] - rad, centre[0] + rad, centre[1] + rad], outline=(30, 30, 30), width=3)
    nose = proj(head_p + head_r @ np.array([0, 0.1, 0.13]))
    d.line([centre, nose], fill=(30, 30, 30), width=2)
    d.text((ox + 6, oy + 4), label, fill=(0, 0, 0))
    # sanity: anything below the floor?
    low = min(p[1] for p in pts.values())
    if low < -0.02:
        d.text((ox + 6, oy + 16), f"BELOW FLOOR {low:.2f}", fill=(220, 0, 0))


def render(data, ex):
    kfs = ex["keyframes"]
    times = []
    for ka, kb in zip(kfs, kfs[1:]):
        times += [ka["t"], (ka["t"] + kb["t"]) / 2]
    times.append(kfs[-1]["t"])
    img = Image.new("RGB", (PANEL_W * len(times), PANEL_H * 2), "white")
    for i, t in enumerate(times):
        ang, pelvis = sample(data, ex, t)
        world = fk(data["rig"], ang, pelvis)
        pts = contact_points(data["rig"], world)
        props = ex.get("props", [])
        draw_panel(img, i * PANEL_W, 0, world, pts, props, "side", f"{ex['id']} t={t:.2f} side")
        draw_panel(img, i * PANEL_W, PANEL_H, world, pts, props, "front", "front")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{ex['id']}.png")
    img.save(path)
    return path


def main():
    with open(DATA, encoding="utf-8") as f:
        data = json.load(f)
    wanted = set(sys.argv[1:])
    for ex in data["exercises"]:
        if not wanted or ex["id"] in wanted:
            print(render(data, ex))


if __name__ == "__main__":
    main()
