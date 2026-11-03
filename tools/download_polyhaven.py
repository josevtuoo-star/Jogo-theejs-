#!/usr/bin/env python3
"""Baixa assets CC0 da Poly Haven (https://polyhaven.com) pela API oficial.

Uso: python3 tools/download_polyhaven.py
Cada asset vai para assets/polyhaven/<tipo>/<id>/ com um arquivo SOURCE.txt
registrando nome, autores, licença (CC0) e URL de origem. Resoluções
escolhidas para celular: texturas e modelos em 1K, HDRI em 2K.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "polyhaven")

# id, tipo, resolução
ASSETS = [
    # Céu e iluminação
    # Terreno e superfícies
    ("forest_floor", "textures", "1k"),
    ("leafy_grass", "textures", "1k"),
    ("brown_mud_leaves_01", "textures", "1k"),
    # Roupas do sobrevivente
    # Modelos (props e natureza com orçamento de polígonos para celular)
    ("wooden_military_crate", "models", "1k"),
    ("old_military_crate", "models", "1k"),
    ("metal_jerrycan_green", "models", "1k"),
    ("russian_food_cans_01", "models", "1k"),
    ("can_rusted", "models", "1k"),
    ("old_tyre", "models", "1k"),
    ("Barrel_02", "models", "1k"),
    ("wooden_barrels_01", "models", "1k"),
    ("concrete_road_barrier_02", "models", "1k"),
    ("utility_box_01", "models", "1k"),
    ("stone_fire_pit", "models", "1k"),
    ("tree_stump_01", "models", "1k"),
    ("rock_moss_set_01", "models", "1k"),
    ("boulder_01", "models", "1k"),
    ("shrub_03", "models", "1k"),
    ("fern_02", "models", "1k"),
    ("dead_tree_trunk", "models", "1k"),
    ("crowbar_01", "models", "1k"),
    ("machete", "models", "1k"),
    ("wooden_axe", "models", "1k"),
    # Etapa 7: armas
    ("baseball_bat", "models", "1k"),
    ("wooden_axe_02", "models", "1k"),
    # Etapa 7: mundo procedural (estrada abandonada, entulho, cavernas)
    ("covered_car", "models", "1k"),
    ("rusted_wheel_rim_01", "models", "1k"),
    ("vintage_suitcase", "models", "1k"),
    ("trashbag", "models", "1k"),
    ("plastic_jerrycan", "models", "1k"),
    ("dry_branches_medium_01", "models", "1k"),
    ("rusty_painted_metal", "textures", "1k"),
    ("rust_coarse_01", "textures", "1k"),
    ("road_damaged", "textures", "1k"),
    ("mossy_rock", "textures", "1k"),
    # Cavernas (etapa 8): estratos da rocha e chão de cascalho
    ("cliff_side", "textures", "1k"),
    ("brown_mud_rocks_01", "textures", "1k"),
    # Etapa 9: tábuas (itens e construções)
    ("weathered_planks", "textures", "1k"),
    # Etapa 9: biomas (chão)
    ("snow_02", "textures", "1k"),
    ("dry_ground_rocks", "textures", "1k"),
    ("forest_leaves_02", "textures", "1k"),
    ("sparse_grass", "textures", "1k"),
    # Etapa 9: vilas e cidades
    ("brick_wall_02", "textures", "1k"),
    ("worn_plaster_wall", "textures", "1k"),
    ("concrete_wall_004", "textures", "1k"),
    ("grey_roof_01", "textures", "1k"),
    ("rusty_corrugated_iron", "textures", "1k"),
    # Etapa 9: vegetação dos biomas (malhas reduzidas por build_world_assets)
    ("shrub_02", "models", "1k"),
    ("shrub_04", "models", "1k"),
    ("weed_plant_02", "models", "1k"),
    ("street_lamp_01", "models", "1k"),
    ("metal_trash_can", "models", "1k"),
]

# Fontes grandes só para gerar impostores (ficam em assets/_source, fora do
# Git e do APK): python3 tools/download_polyhaven.py --fontes
SOURCES = [
    ("tree_small_02", "models", "1k"),
    ("quiver_tree_01", "models", "1k"),
]

# Mapas usados de cada textura (formato jpg; normal no padrão OpenGL usado pelo Godot).
TEXTURE_MAPS = {"Diffuse": "albedo", "nor_gl": "normal", "arm": "arm"}


def fetch_json(url):
    out = subprocess.run(["curl", "-sSfL", "-m", "60", url], capture_output=True, check=True).stdout
    return json.loads(out)


def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["curl", "-sSfL", "-m", "600", "-o", path, url], check=True)


def main():
    sources = "--fontes" in sys.argv
    only = set(a for a in sys.argv[1:] if not a.startswith("--"))
    for asset_id, kind, res in (SOURCES if sources else ASSETS):
        if only and asset_id not in only:
            continue
        info = fetch_json(f"https://api.polyhaven.com/info/{asset_id}")
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
        folder = os.path.join(ROOT, kind, asset_id)
        if sources:
            folder = os.path.join(ROOT, "..", "_source", asset_id)
        if kind == "hdris":
            entry = files["hdri"][res]["hdr"]
            download(entry["url"], os.path.join(folder, f"{asset_id}_{res}.hdr"))
        elif kind == "textures":
            for key, short in TEXTURE_MAPS.items():
                entry = files[key][res]["jpg"]
                download(entry["url"], os.path.join(folder, f"{asset_id}_{short}_{res}.jpg"))
        else:
            entry = files["gltf"][res]["gltf"]
            download(entry["url"], os.path.join(folder, os.path.basename(entry["url"])))
            for rel, inc in entry.get("include", {}).items():
                download(inc["url"], os.path.join(folder, rel))
        authors = ", ".join(info.get("authors", {}).keys())
        with open(os.path.join(folder, "SOURCE.txt"), "w", encoding="utf-8") as f:
            f.write(f"Nome: {info.get('name')}\nAutores: {authors}\nLicença: CC0 1.0 (Poly Haven)\n")
            f.write(f"Origem: https://polyhaven.com/a/{asset_id}\nResolução: {res}\n")
            if "polycount" in info:
                f.write(f"Polígonos: {info['polycount']}\n")
        size = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(folder) for fn in fns)
        print(f"{kind:9s} {asset_id:28s} {res}  {size / 1e6:6.2f} MB  autores: {authors}")


if __name__ == "__main__":
    sys.exit(main())
