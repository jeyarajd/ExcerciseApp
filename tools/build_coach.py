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

COACHES = {
    "female": {
        "macro": {"gender": 0.0, "age": 0.45, "muscle": 0.62, "weight": 0.45, "proportions": 0.8, "height": 0.55,
                  "cupsize": 0.45, "firmness": 0.6, "race": {"asian": 0.25, "caucasian": 0.55, "african": 0.2}},
        "skin": "skins/cutoff3d_indian_female_skin/cutoff3d_indian_female_skin.mhmat",
        "hair": "hair/ponytail01/ponytail01.mhclo",
        "eyebrows": "eyebrows/eyebrow010/eyebrow010.mhclo",
        "eyelashes": "eyelashes/eyelashes02/eyelashes02.mhclo",
        "clothes": ["clothes/female_sportsuit01/female_sportsuit01.mhclo", "clothes/shoes05/shoes05.mhclo"],
    },
    "male": {
        "macro": {"gender": 1.0, "age": 0.45, "muscle": 0.7, "weight": 0.45, "proportions": 0.8, "height": 0.6,
                  "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.25, "caucasian": 0.55, "african": 0.2}},
        "skin": "skins/toigo_light_skin_male_bronze/toigo_light_skin_male_bronze.mhmat",
        "hair": "hair/short02/short02.mhclo",
        "eyebrows": "eyebrows/eyebrow001/eyebrow001.mhclo",
        "eyelashes": "eyelashes/eyelashes01/eyelashes01.mhclo",
        "clothes": ["clothes/toigo_basic_tucked_t-shirt/toigo_basic_tucked_t-shirt.mhclo",
                    "clothes/toigo_wool_pants/toigo_wool_pants.mhclo", "clothes/shoes05/shoes05.mhclo"],
        # Brand orange for the plain grey t-shirt (multiplied into its texture).
        "tint": {"toigo_basic_tucked_t-shirt": (1.0, 0.56, 0.2)},
    },
}


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
            tint = next((t for key, t in tints.items() if key in mat.name), None)
            if tint:
                px = np.array(pixels, dtype=np.float32).reshape(-1, 4)
                # Lift the grey texture to near-white first so the tint reads as a strong colour.
                shade = np.clip(px[:, :3].mean(axis=1, keepdims=True) * 1.6, 0, 1)
                px[:, :3] = shade * np.array(tint, dtype=np.float32)
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
    fix_materials(body, spec.get("tint", {}))

    path = os.path.join(OUT, f"coach_{name}.usdz")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.usd_export(filepath=path, selected_objects_only=True, export_animation=False,
                          export_armatures=True, export_materials=True, generate_preview_surface=True,
                          export_textures_mode="NEW", overwrite_textures=True, convert_orientation=False,
                          evaluation_mode="RENDER")
    print("EXPORTED", path, len(body.data.vertices), "verts,", len(armature.data.bones), "bones")


for coach_name, coach_spec in COACHES.items():
    if len(sys.argv) > sys.argv.index("--") + 2 and coach_name not in sys.argv[sys.argv.index("--") + 2:]:
        continue
    build(coach_name, coach_spec)
