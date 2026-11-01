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
    ("gravel_floor", "textures", "1k"),
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
    for asset_id, kind, res in ASSETS:
        info = fetch_json(f"https://api.polyhaven.com/info/{asset_id}")
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
        folder = os.path.join(ROOT, kind, asset_id)
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
