"""Builds the realistic coach models (FloorAge/Resources/coach_female.usdz, coach_male.usdz).

Runs headless in Blender 4.2+ with the MPFB add-on and these CC0 MakeHuman asset packs installed:
makehuman_system_assets, skins01, skins02, hair01, shirts01, pants01, shoes01
(https://static.makehumancommunity.org/assets/assetpacks/index.html). Everything exported is CC0.

    blender -b --python tools/build_coach.py -- <output dir> [female|male]

The app drives the exported skeleton (MPFB "game_engine" rig) from exercises.json poses; see
FloorAge/Avatar/RealisticCoach.swift for the bone mapping. Blender's Z-up axes are kept in the file
and converted to the app's Y-up on the skeleton root at runtime.
"""

import os
import sys
import tempfile

import numpy as np

import addon_utils
import bpy

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
DATA = LocationService.get_user_data()

# Brand colours from App/Theme.swift: the calories/mat teal and the steps/Floor Age orange.
TEAL = (0.02, 0.42, 0.45)
ORANGE = (1.0, 0.56, 0.2)

# v2 looks: South Asian coaches in their early 30s (the app speaks Indian English by default and
# coaches whole families), athletic but attainable bodies, and matching teal-and-orange training
# kit so both read as one brand. Clothes that show the knees and hips make every demo easier to read.
COACHES = {
    "female": {
        "macro": {"gender": 0.0, "age": 0.54, "muscle": 0.6, "weight": 0.48, "proportions": 0.85, "height": 0.52,
                  "cupsize": 0.42, "firmness": 0.6, "race": {"asian": 0.7, "caucasian": 0.2, "african": 0.1}},
        "skin": "skins/cutoff3d_indian_female_skin/cutoff3d_indian_female_skin.mhmat",
        "hair": "hair/ponytail01/ponytail01.mhclo",
        "eyebrows": "eyebrows/eyebrow010/eyebrow010.mhclo",
        "eyelashes": "eyelashes/eyelashes02/eyelashes02.mhclo",
        # Fitted training tee over the sports suit's leggings (its crop top is cut away).
        "clothes": ["clothes/female_sportsuit01/female_sportsuit01.mhclo",
                    "clothes/joepal_crude_t-shirt_female/joepal_crude_t-shirt_female.mhclo", "clothes/shoes05/shoes05.mhclo"],
        "trim_above_waist": ["female_sportsuit01"],
        "recolor": {"joepal_crude_t-shirt_female": ("tint", TEAL), "female_sportsuit01": ("blue_to", TEAL),
                    "shoes05": ("green_to", ORANGE)},
        "hair_color": (0.035, 0.025, 0.02),
        "skin_tone": (0.86, 0.76, 0.7),
    },
    "male": {
        "macro": {"gender": 1.0, "age": 0.6, "muscle": 0.68, "weight": 0.5, "proportions": 0.85, "height": 0.6,
                  "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.7, "caucasian": 0.2, "african": 0.1}},
        "skin": "skins/toigo_light_skin_male_bronze/toigo_light_skin_male_bronze.mhmat",
        "skin_tone": (0.78, 0.7, 0.66),
        "hair": "hair/short04/short04.mhclo",
        "eyebrows": "eyebrows/eyebrow001/eyebrow001.mhclo",
        "eyelashes": "eyelashes/eyelashes01/eyelashes01.mhclo",
        # Training tee over running tights (the sports suit, cut at the waist) and shorts.
        "clothes": ["clothes/female_sportsuit01/female_sportsuit01.mhclo", "clothes/cortu_jeans_shorts/cortu_jeans_shorts.mhclo",
                    "clothes/elvs_crude_t-shirt_male/elvs_crude_t-shirt_male.mhclo", "clothes/shoes05/shoes05.mhclo"],
        "trim_above_waist": ["female_sportsuit01"],
        "inflate": {"cortu_jeans_shorts": 0.012},
        "no_normal_map": ["cortu_jeans_shorts"],
        "recolor": {"elvs_crude_t-shirt_male": ("tint", TEAL), "cortu_jeans_shorts": ("charcoal", None),
                    "female_sportsuit01": ("blue_to", TEAL), "shoes05": ("green_to", ORANGE)},
        "hair_color": (0.03, 0.022, 0.018),
    },
}


def recolor_pixels(px, mode, color):
    """px: (N, 4) float RGBA. Returns recoloured pixels for the brand kit."""
    rgb = px[:, :3]
    lum = (rgb * np.array([0.3, 0.59, 0.11], dtype=np.float32)).sum(axis=1, keepdims=True)
    c = np.array(color or (0, 0, 0), dtype=np.float32)
    if mode == "tint":
        # Lift a pale texture so the tint reads strongly, keep its folds and shading.
        shade = np.clip(lum / max(float(np.percentile(lum, 90)), 1e-3), 0.55, 1.1)
        rgb[:] = np.clip(shade * c, 0, 1)
    elif mode == "charcoal":
        rgb[:] = np.clip(lum * 0.55, 0, 1) * np.array([0.9, 0.93, 1.0], dtype=np.float32)
    elif mode in ("blue_to", "green_to"):
        r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
        if mode == "blue_to":
            mask = (b > r + 0.12) & (b > g + 0.05)
        else:
            mask = (g > r + 0.12) & (g > b + 0.08)
        shade = np.clip(lum[mask] / max(float(np.median(lum[mask])) if mask.any() else 1, 1e-3), 0.6, 1.2)
        rgb[mask] = np.clip(shade * c, 0, 1)
        if mode == "blue_to":
            # Deepen the grey leggings to near-black.
            dark = (~mask) & (lum[:, 0] < 0.3)
            rgb[dark] *= 0.45
    return px


def trim_above_waist(obj, armature):
    """Delete the part of a clothing mesh above the waist (keeps just the tights of the sports suit)."""
    import bmesh
    thigh = armature.data.bones.get("thigh_l")
    spine = armature.data.bones.get("spine_01")
    waist = (armature.matrix_world @ spine.head_local).z if spine else None
    if waist is None:
        return
    waist -= 0.02
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    mw = obj.matrix_world
    doomed = [v for v in bm.verts if (mw @ v.co).z > waist]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    print("TRIMMED", obj.name, len(doomed), "verts above", round(waist, 3))


def find(relative):
    for root in (DATA, LocationService.get_mpfb_data()):
        path = os.path.join(root, relative)
        if os.path.exists(path):
            return path
    raise FileNotFoundError(relative)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


# Materials that need alpha cut-outs; everything else is exported fully opaque.
CUTOUT = ("eyebrow", "eyelash", "hair", "ponytail", "short0")
TEXTURES = tempfile.mkdtemp(prefix="coach_textures_")


def image_node_for(mat, socket_name):
    socket = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs[socket_name]
    for link in socket.links:
        if link.from_node.type == "TEX_IMAGE":
            return link.from_node
    return None


def fix_materials(mesh, tints):
    """RealityKit imports USD opacity as a blend using the texture's colour, not its alpha, so dark
    clothes and hair came out see-through. Opaque parts get no opacity at all; cut-outs get a mask
    texture with the alpha copied into every channel. Colour textures are saved as smaller JPEGs."""
    for mat in mesh.data.materials:
        tree = mat.node_tree
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        alpha = bsdf.inputs["Alpha"]
        for link in list(alpha.links):
            tree.links.remove(link)
        # MakeHuman routes colour through mix nodes (intensity, AO); wire the texture straight in.
        color = tree.nodes.get("diffuseTexture") or image_node_for(mat, "Base Color")
        if color is not None and color.type == "TEX_IMAGE":
            tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
        cutout = any(key in mat.name.lower() for key in CUTOUT)
        if color is not None and color.image is not None:
            src = color.image
            w, h = src.size
            pixels = list(src.pixels)
            if cutout:
                mask = bpy.data.images.new(f"{src.name}_mask", w, h, alpha=True)
                a = pixels[3::4]
                mask.pixels = [v for value in a for v in (value, value, value, value)]
                if max(w, h) > 1024:
                    mask.scale(1024, 1024)
                mask.filepath_raw = os.path.join(TEXTURES, f"{os.path.splitext(src.name)[0]}_mask.png")
                mask.file_format = "PNG"
                mask.save()
                mask.colorspace_settings.name = "Non-Color"
                node = tree.nodes.new("ShaderNodeTexImage")
                node.image = mask
                tree.links.new(node.outputs["Alpha"], alpha)
                if hasattr(mat, "blend_method"):
                    mat.blend_method = "CLIP"
            # Colour as a JPEG (cut-outs too: their alpha now lives in the mask), at most
            # 2048 px for skin and 1024 px for the rest.
            limit = 2048 if "body" in mat.name.lower() else 1024
            copy = bpy.data.images.new(f"{src.name}_jpg", w, h, alpha=False)
            rule = next((r for key, r in tints.items() if key in mat.name), None)
            if rule:
                px = np.array(pixels, dtype=np.float32).reshape(-1, 4)
                px = recolor_pixels(px, *rule)
                pixels = px.ravel().tolist()
            copy.pixels = pixels
            if max(w, h) > limit:
                copy.scale(limit, limit)
            copy.filepath_raw = os.path.join(TEXTURES, f"{os.path.splitext(src.name)[0]}.jpg")
            copy.file_format = "JPEG"
            bpy.context.scene.render.image_settings.quality = 85
            copy.save()
            color.image = copy
        print("MATERIAL", mat.name, "cutout" if cutout else "opaque")


def tune_materials(mesh, spec):
    """Softer, more lifelike surfaces: matte fabric, a little sheen on skin, darker natural hair,
    and a warmer skin tone where asked. Only plain PBR values, which USD Preview Surface keeps."""
    for mat in mesh.data.materials:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        name = mat.name.lower()
        bsdf.inputs["Metallic"].default_value = 0.0
        if "body" in name or "skin" in name:
            bsdf.inputs["Roughness"].default_value = 0.68
            if "Specular IOR Level" in bsdf.inputs:
                bsdf.inputs["Specular IOR Level"].default_value = 0.35
            tone = spec.get("skin_tone")
            if tone:
                color = next((l.from_node for l in bsdf.inputs["Base Color"].links if l.from_node.type == "TEX_IMAGE"), None)
                if color is not None and color.image is not None:
                    img = color.image
                    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
                    px[:, :3] = np.clip(px[:, :3] * np.array(tone, dtype=np.float32), 0, 1)
                    img.pixels = px.ravel().tolist()
                    img.save()
        elif any(k in name for k in ("hair", "ponytail", "short0")):
            bsdf.inputs["Roughness"].default_value = 0.62
            hc = spec.get("hair_color")
            if hc:
                color = next((l.from_node for l in bsdf.inputs["Base Color"].links if l.from_node.type == "TEX_IMAGE"), None)
                if color is not None and color.image is not None:
                    img = color.image
                    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
                    lum = px[:, :3].mean(axis=1, keepdims=True)
                    px[:, :3] = np.clip(np.array(hc, dtype=np.float32) + lum * 0.35 * np.array(hc, dtype=np.float32) * 6, 0, 1)
                    img.pixels = px.ravel().tolist()
                    img.save()
        elif "eye" not in name:
            bsdf.inputs["Roughness"].default_value = 0.85
            if any(k in name for k in spec.get("no_normal_map", [])):
                # Denim normals read wrong on training shorts, and the map alone is 5 MB.
                for link in list(bsdf.inputs["Normal"].links):
                    mat.node_tree.links.remove(link)


def build(name, spec):
    clear_scene()
    # Keep the helper and joint vertex groups: the rig uses them to place its bones.
    body = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                     feet_on_ground=True, scale=0.1, macro_detail_dict=spec["macro"])
    TargetService.bake_targets(body)
    HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    HumanService.set_character_skin(find(spec["skin"]), body, skin_type="GAMEENGINE", material_instances=False)
    HumanService.add_mhclo_asset(find("eyes/high-poly/high-poly.mhclo"), body, asset_type="Eyes", subdiv_levels=0)
    for kind in ("eyebrows", "eyelashes"):
        HumanService.add_mhclo_asset(find(spec[kind]), body, asset_type=kind.capitalize(), subdiv_levels=0)
    HumanService.add_mhclo_asset(find(spec["hair"]), body, asset_type="Hair", subdiv_levels=0)
    for clothes in spec["clothes"]:
        HumanService.add_mhclo_asset(find(clothes), body, asset_type="Clothes", subdiv_levels=0)

    armature = body.parent
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in meshes:
        if any(key in obj.name for key in spec.get("trim_above_waist", [])):
            trim_above_waist(obj, armature)
        for key, amount in spec.get("inflate", {}).items():
            if key in obj.name:
                # Sit this layer clearly outside the tights so it isn't hidden under them.
                for v in obj.data.vertices:
                    v.co += v.normal * amount
                print("INFLATED", obj.name, amount)
    # Apply everything except the armature (helper masks, clothes-hiding masks, subdivision), then
    # join into one skinned mesh so the app poses a single skeleton.
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            if mod.type != "ARMATURE":
                try:
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                except RuntimeError as error:
                    print("could not apply", obj.name, mod.name, error)
                    obj.modifiers.remove(mod)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = armature.name = f"coach_{name}"
    fix_materials(body, spec.get("recolor", {}))
    tune_materials(body, spec)

    path = os.path.join(OUT, f"coach_{name}.usdz")
    bpy.ops.object.select_all(action="SELECT")
    options = dict(filepath=path, selected_objects_only=True, export_animation=False,
                   export_armatures=True, export_materials=True, generate_preview_surface=True,
                   overwrite_textures=True, convert_orientation=False, evaluation_mode="RENDER")
    try:
        bpy.ops.wm.usd_export(export_textures_mode="NEW", **options)
    except TypeError:  # Blender 4.2 names it export_textures.
        bpy.ops.wm.usd_export(export_textures=True, **options)
    print("EXPORTED", path, len(body.data.vertices), "verts,", len(armature.data.bones), "bones")


def render_preview(name, out_dir):
    """Studio preview (front three-quarter and side) on a transparent background, for review only."""
    import math
    from mathutils import Vector
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = int(os.environ.get("PREVIEW_SAMPLES", "48"))
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = 900, 1350
    scene.view_settings.view_transform = "Standard"
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.25
    world.node_tree.nodes["Background"].inputs[0].default_value = (1.0, 0.95, 0.9, 1)

    def light(loc, energy, size, color=(1, 1, 1)):
        data = bpy.data.lights.new("l", "AREA")
        data.energy, data.size, data.color = energy, size, color
        obj = bpy.data.objects.new("l", data)
        scene.collection.objects.link(obj)
        obj.location = loc
        direction = Vector((0, 0, 1.0)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    light((2.2, -2.6, 2.4), 260, 2.0, (1.0, 0.95, 0.9))
    light((-2.6, -1.8, 1.6), 110, 2.5, (0.9, 0.95, 1.0))
    light((0.5, 2.8, 2.6), 220, 1.5)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 70
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, angle in (("front", -25), ("side", -90)):
        a = math.radians(angle)
        dist = 4.3
        cam.location = (dist * math.sin(a), -dist * math.cos(a), 0.95)
        target = Vector((0, 0, 0.88))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"preview_{name}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)
    face = os.path.join(out_dir, f"preview_{name}_face.png")
    cam_data.lens = 120
    h = 1.68 if name == "male" else 1.58
    cam.location = (-0.9, -2.3, h + 0.02)
    target = Vector((0, 0, h - 0.04))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = 900, 900
    scene.render.filepath = face
    bpy.ops.render.render(write_still=True)
    print("RENDERED", face)


for coach_name, coach_spec in COACHES.items():
    if len(sys.argv) > sys.argv.index("--") + 2 and coach_name not in sys.argv[sys.argv.index("--") + 2:]:
        continue
    build(coach_name, coach_spec)
    if os.environ.get("PREVIEW"):
        render_preview(coach_name, os.environ["PREVIEW"])
