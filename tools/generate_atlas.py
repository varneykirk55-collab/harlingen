#!/usr/bin/env python3
"""Generate the Harlingen Development Atlas (JSON + Markdown) from project data.

Read-only against the Godot project root; regenerable anytime via:
  python generate_harlingen_atlas.py --project <path> --out-dir <dir>
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import gzip
import json
import math
from pathlib import Path
import re
from typing import Any


DEFAULT_PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = DEFAULT_PROJECT / "docs"
EXT_RES_RE = re.compile(r'^\[ext_resource\s+type="([^"]+)"\s+path="([^"]+)"', re.MULTILINE)


def tile_for_xz(x: float, z: float) -> str:
    ix = max(-3, min(2, math.floor(x / 2000.0)))
    iz = max(-3, min(2, math.floor(z / 2000.0)))
    return f"{ix:+03d}_{iz:+03d}"


def centroid_approx(geom: dict[str, Any]) -> tuple[float, float]:
    t = geom.get("type")
    coords = geom.get("coordinates")
    if not coords:
        return (0.0, 0.0)
    if t == "Point":
        return (float(coords[0]), float(coords[1]))
    if t == "LineString":
        pts = coords
    elif t == "Polygon":
        pts = coords[0]
    elif t == "MultiLineString":
        pts = coords[0]
    elif t == "MultiPolygon":
        pts = coords[0][0]
    else:
        return (0.0, 0.0)
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def scan_polyhaven(root: Path) -> dict[str, Any]:
    ph_dir = root / "materials" / "polyhaven"
    sets = []
    terrain_slots = []
    hdris = []
    if not ph_dir.exists():
        return {"pbr_sets": [], "terrain_packed": [], "hdris": []}

    for child in sorted(ph_dir.iterdir()):
        if not child.is_dir():
            continue
        if child.name == "hdri":
            for f in sorted(child.glob("*.hdr")):
                hdris.append({"id": f.stem, "path": f"materials/polyhaven/hdri/{f.name}", "size_mb": round(f.stat().st_size / 1e6, 2)})
        elif child.name == "terrain":
            for f in sorted(child.glob("*.png")):
                terrain_slots.append({"file": f.name, "path": f"materials/polyhaven/terrain/{f.name}", "size_mb": round(f.stat().st_size / 1e6, 2)})
        else:
            maps = sorted(f.name for f in child.iterdir() if f.is_file() and f.suffix.lower() in {".jpg", ".png"})
            res = "2K" if any("_2k" in m for m in maps) else ("1K" if any("_1k" in m for m in maps) else "unknown")
            sets.append({
                "id": child.name,
                "resolution": res,
                "path": f"materials/polyhaven/{child.name}/",
                "map_count": len(maps),
                "maps": maps,
            })
    return {"pbr_sets": sets, "terrain_packed": terrain_slots, "hdris": hdris}


def scan_assets(root: Path) -> dict[str, Any]:
    assets_dir = root / "assets"
    top_glbs = sorted(f.name for f in assets_dir.glob("*.glb"))

    def list_dir(rel: str, exts: set[str]) -> list[str]:
        d = root / rel
        if not d.exists():
            return []
        return sorted(
            str(p.relative_to(root)).replace("\\", "/")
            for p in d.rglob("*")
            if p.is_file() and p.suffix.lower() in exts
        )

    return {
        "prop_kit_glbs": top_glbs,
        "jackson_hero": {
            "scenes": list_dir("assets/jackson_hero", {".tscn"}),
            "glbs": list_dir("assets/jackson_hero", {".glb"}),
            "materials": list_dir("assets/jackson_hero", {".tres"}),
            "scripts": list_dir("assets/jackson_hero", {".gd"}),
        },
        "landmarks": {
            "scenes": list_dir("assets/landmarks", {".tscn"}),
            "glbs": list_dir("assets/landmarks", {".glb"}),
        },
        "street_realism_props": list_dir("assets/street_realism", {".glb"}),
        "signage_scenes": list_dir("assets/signage", {".tscn"}),
        "signage_texture_count": len(list_dir("assets/signage", {".png", ".jpg"})),
        "gameplay_assets": {
            "character": list_dir("assets/character", {".glb"}),
            "vehicle": list_dir("assets/vehicle", {".glb"}),
            "police_interceptor": list_dir("assets/police_interceptor", {".glb", ".tscn"}),
            "weapons": list_dir("assets/weapons", {".glb"}),
        },
    }


def scan_sources(root: Path) -> dict[str, Any]:
    by_tile_named: dict[str, list[dict[str, Any]]] = defaultdict(list)
    by_tile_counts: dict[str, Counter] = defaultdict(Counter)
    target_queries = {
        "whataburger": ["whataburger"],
        "walmart": ["walmart"],
        "heb": ["h-e-b", "heb", "h e b"],
        "valley_baptist": ["valley baptist"],
        "heart_clinic": ["heart", "cardio", "vascular"],
        "church": ["church", "baptist", "catholic", "methodist", "lutheran", "chapel", "iglesia", "nazarene", "pentecostal"],
        "iwo_jima": ["iwo jima"],
        "police": ["police"],
        "mckelvey": ["mckelvey"],
    }
    landmark_hits: dict[str, list[dict[str, Any]]] = defaultdict(list)
    fuel_sites: list[dict[str, Any]] = []

    for fname in ("osm_local.geojson.gz", "overture_local.geojson.gz"):
        fpath = root / "source" / fname
        if not fpath.exists():
            continue
        with gzip.open(fpath, "rt", encoding="utf-8") as f:
            data = json.load(f)
        for feat in data.get("features", []):
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            x, z = centroid_approx(geom)
            tid = tile_for_xz(x, z)
            if props.get("building"):
                by_tile_counts[tid]["buildings_" + ("osm" if "osm" in fname else "overture")] += 1
            if props.get("amenity") == "parking":
                by_tile_counts[tid]["parking_lots"] += 1
            if props.get("railway"):
                by_tile_counts[tid]["railway_ways"] += 1
            if props.get("amenity") == "fuel" and "osm" in fname:
                fuel_sites.append({
                    "id": feat.get("id"),
                    "name": props.get("name") or "(unnamed fuel)",
                    "tile": tid,
                    "x": round(x, 1),
                    "z": round(z, 1),
                })

            name = str(props.get("name") or "").strip()
            brand = str(props.get("brand") or "").strip()
            if not name:
                continue
            nl = f"{name} {brand}".lower()
            if props.get("building") or props.get("amenity") or props.get("shop") or props.get("leisure"):
                by_tile_counts[tid]["named_pois"] += 1
                if len(by_tile_named[tid]) < 120:
                    by_tile_named[tid].append({"name": name, "id": feat.get("id"), "x": round(x, 1), "z": round(z, 1)})
            for key, terms in target_queries.items():
                if any(t in nl for t in terms):
                    landmark_hits[key].append({
                        "id": feat.get("id"),
                        "name": name,
                        "tile": tid,
                        "x": round(x, 1),
                        "z": round(z, 1),
                        "source": fname,
                    })

    geo_sites = []
    gs_path = root / "source" / "geographic_sites.geojson"
    if gs_path.exists():
        gs = json.loads(gs_path.read_text(encoding="utf-8"))
        for feat in gs.get("features", []):
            props = feat.get("properties") or {}
            x, z = centroid_approx(feat.get("geometry") or {})
            geo_sites.append({
                "id": feat.get("id"),
                "name": props.get("name"),
                "kind": props.get("kind"),
                "tile": tile_for_xz(x, z),
                "x": round(x, 1),
                "z": round(z, 1),
            })

    return {
        "by_tile_counts": {k: dict(v) for k, v in by_tile_counts.items()},
        "fuel_sites_osm": fuel_sites,
        "geographic_sites": geo_sites,
        "target_landmark_hits": dict(landmark_hits),
    }


def build_atlas(root: Path) -> dict[str, Any]:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    sources = scan_sources(root)
    polyhaven = scan_polyhaven(root)
    assets = scan_assets(root)

    # Map manifest landmarks by tile
    landmarks_by_tile: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for lm in manifest.get("landmarks", []):
        tid = tile_for_xz(float(lm["x"]), float(lm["z"]))
        landmarks_by_tile[tid].append({"name": lm["name"], "layer": lm["layer"], "source": lm["source"], "x": lm["x"], "z": lm["z"]})

    # Street realism per-tile metrics from manifest
    sr_tiles = manifest.get("street_realism", {}).get("districts", {})

    tiles_out = []
    totals = Counter()

    for t in manifest["tiles"]:
        tid = t["id"]
        tile_dir = root / "tiles" / tid
        tscn_path = tile_dir / "district.tscn"
        ext_scenes = []
        if tscn_path.exists():
            txt = tscn_path.read_text(encoding="utf-8")
            ext_scenes = [p for typ, p in EXT_RES_RE.findall(txt) if typ == "PackedScene" and not p.startswith(f"res://tiles/{tid}/")]

        sf_counts = {}
        sf_path = tile_dir / "StreetFurniture.json"
        if sf_path.exists():
            sf_data = json.loads(sf_path.read_text(encoding="utf-8"))
            sf_counts = {k: len(v) for k, v in sf_data.items()}

        inst_counts = {}
        inst_path = tile_dir / "instances.json"
        if inst_path.exists():
            inst_data = json.loads(inst_path.read_text(encoding="utf-8"))
            inst_counts = {k: len(v) for k, v in inst_data.items()}

        layers = {k: v.get("triangles", 0) for k, v in t.get("layers", {}).items()}
        glb_mb = round(sum(f.stat().st_size for f in tile_dir.glob("*.glb")) / 1e6, 2)
        sr = sr_tiles.get(tid, {})
        sd = t.get("street_details", {})
        counts = t.get("counts", {})
        bldg_count = counts.get("tagged_height", 0) + counts.get("estimated", 0)
        curb_m = float(sd.get("curb_metres", 0.0))
        crosswalks = int(sr.get("crosswalks", 0))
        src_counts = sources["by_tile_counts"].get(tid, {})

        totals["buildings"] += bldg_count
        totals["instances"] += t.get("instances", 0)
        totals["triangles"] += sum(layers.values())
        totals["curb_m"] += curb_m
        totals["crosswalks"] += crosswalks
        totals["signals"] += sf_counts.get("signal0", 0) + sf_counts.get("signal1", 0)
        if "Sidewalks" in layers:
            totals["tiles_with_sidewalks"] += 1
        if "Bridges" in layers:
            totals["tiles_with_legacy_bridges"] += 1
        if "ElevatedRoads" in layers:
            totals["tiles_with_elevated_roads"] += 1

        tiles_out.append({
            "id": tid,
            "origin_local_xz": [t["x"], t["z"]],
            "buildings": bldg_count,
            "instances": t.get("instances", 0),
            "total_triangles": sum(layers.values()),
            "glb_disk_mb": glb_mb,
            "has_sidewalks": "Sidewalks" in layers,
            "has_elevated_roads": "ElevatedRoads" in layers,
            "has_legacy_bridges": "Bridges" in layers,
            "curb_m": round(curb_m, 1),
            "crosswalks": crosswalks,
            "signals": sf_counts.get("signal0", 0) + sf_counts.get("signal1", 0),
            "layers_triangles": layers,
            "street_details": sd,
            "street_furniture": sf_counts,
            "prop_instances": inst_counts,
            "external_scenes": ext_scenes,
            "source_counts": src_counts,
            "manifest_landmark_count": len(landmarks_by_tile.get(tid, [])),
        })

    tools_list = sorted(f.name for f in (root / "tools").glob("*") if f.is_file() and f.suffix in {".py", ".gd"})
    scripts_list = sorted(str(p.relative_to(root)).replace("\\", "/") for p in (root / "scripts").rglob("*.gd"))
    scenes_list = sorted(str(p.relative_to(root)).replace("\\", "/") for p in (root / "scenes").rglob("*.tscn"))

    landmarks_registry = {}
    lm_reg_path = root / "docs" / "HARLINGEN_LANDMARKS.json"
    if lm_reg_path.exists():
        landmarks_registry = json.loads(lm_reg_path.read_text(encoding="utf-8"))

    citywide_systems = {
        "integration_owner": {
            "agent": "atlas-inventor",
            "owns": [
                "preview/tile.gd",
                "tools/generate_atlas.py",
                "docs/HARLINGEN_ATLAS.json",
                "docs/HARLINGEN_DEVELOPMENT_ATLAS.md",
            ],
        },
        "worker_b_roads_sidewalks": {
            "agent": "roads-sidewalks",
            "script": "scripts/citywide/road_sidewalk_detailer.gd",
            "class_name": "RoadSidewalkDetailer",
            "owns": ["materials/citywide/roads/", "scripts/citywide/road_sidewalk_detailer.gd"],
            "material_count": len(list((root / "materials" / "citywide" / "roads").glob("*.tres"))) if (root / "materials" / "citywide" / "roads").exists() else 0,
        },
        "worker_c_building_facades": {
            "agent": "building-facades",
            "script": "scripts/citywide/building_facade_detailer.gd",
            "class_name": "BuildingFacadeDetailer",
            "owns": ["materials/citywide/facades/", "scripts/citywide/building_facade_detailer.gd"],
            "material_count": len(list((root / "materials" / "citywide" / "facades").glob("*.tres"))) if (root / "materials" / "citywide" / "facades").exists() else 0,
        },
        "worker_d_vegetation_props": {
            "agent": "vegetation-props",
            "script": "scripts/citywide/vegetation_props_detailer.gd",
            "class_name": "VegetationPropsDetailer",
            "owns": ["assets/citywide/props/", "scripts/citywide/vegetation_props_detailer.gd"],
        },
        "worker_e_vehicles_commercial": {
            "agent": "vehicles-commercial",
            "script": "scripts/citywide/vehicles_commercial_detailer.gd",
            "class_name": "VehiclesCommercialDetailer",
            "owns": [
                "assets/citywide/commercial/",
                "docs/HARLINGEN_LANDMARKS.json",
                "scripts/citywide/vehicles_commercial_detailer.gd",
            ],
            "material_count": len(list((root / "assets" / "citywide" / "commercial").glob("*.tres"))) if (root / "assets" / "citywide" / "commercial").exists() else 0,
        },
    }

    return {
        "schema_version": "1.1.0",
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "project_root": str(root),
        "coordinate_system": {
            "epsg": manifest["origin_epsg"],
            "origin_easting": manifest["origin_easting"],
            "origin_northing": manifest["origin_northing"],
            "tile_size_m": manifest["tile_size"],
            "local_extent_m": manifest["local_extent"],
            "vertical_datum": manifest["vertical"],
        },
        "citywide_totals": {
            "tile_count": len(tiles_out),
            "buildings": totals["buildings"],
            "prop_instances": totals["instances"],
            "tile_triangles": totals["triangles"],
            "curb_m": round(totals["curb_m"], 1),
            "crosswalks": totals["crosswalks"],
            "signals": totals["signals"],
            "tiles_with_sidewalks": totals["tiles_with_sidewalks"],
            "tiles_with_legacy_bridges": totals["tiles_with_legacy_bridges"],
            "tiles_with_elevated_roads": totals["tiles_with_elevated_roads"],
            "polyhaven_pbr_sets": len(polyhaven["pbr_sets"]),
            "manifest_landmarks": len(manifest.get("landmarks", [])),
        },
        "city_generation_pipeline": {
            "tools": tools_list,
            "runtime_preview": ["preview/Harlingen.tscn", "preview/world.gd", "preview/tile.gd", "preview/walker.gd"],
            "gameplay_scripts": scripts_list,
            "gameplay_scenes": scenes_list,
        },
        "citywide_detailing_systems": citywide_systems,
        "assets_inventory": assets,
        "polyhaven_inventory": polyhaven,
        "harlingen_landmarks": {
            "geographic_sites": sources["geographic_sites"],
            "fuel_sites_osm": sources["fuel_sites_osm"],
            "target_landmark_hits": sources["target_landmark_hits"],
            "verified_registry_summary": {k: len(v) if isinstance(v, list) else v for k, v in landmarks_registry.items()},
        },
        "tiles": tiles_out,
    }


def render_markdown(atlas: dict[str, Any]) -> str:
    cs = atlas["coordinate_system"]
    tot = atlas["citywide_totals"]
    lines = [
        "# Harlingen Development Atlas",
        "",
        f"> Auto-generated from `{atlas['project_root']}` on `{atlas['generated_at_utc']}` (schema `{atlas['schema_version']}`).",
        "",
        "## 1. Project & Coordinate System",
        f"- **CRS**: `EPSG:{cs['epsg']}` (Origin Easting `{cs['origin_easting']}`, Northing `{cs['origin_northing']}`)",
        f"- **Grid**: `{tot['tile_count']}` tiles (`{cs['tile_size_m']} m` each), local extent `{cs['local_extent_m']}`",
        f"- **Citywide Totals**: `{tot['buildings']:,}` buildings | `{tot['tile_triangles']:,}` tile triangles | `{tot['prop_instances']:,}` prop instances | `{tot['curb_m']:,.1f} m` curbs | `{tot['crosswalks']:,}` crosswalks | `{tot['signals']}` signals",
        f"- **Coverage**: `{tot['tiles_with_sidewalks']}/36` tiles with Sidewalks | `{tot['tiles_with_elevated_roads']}/36` with ElevatedRoads | `{tot['tiles_with_legacy_bridges']}/36` with legacy `Bridges.glb`",
        "",
        "## 2. 36-District Tile Matrix",
        "",
        "| Tile | Origin (X, Z) | Bldgs | Tris | MB | Sidewalks | Curbs (m) | Crosswalks | Signals | Legacy Bridge Tris | Elevated Tris | External Scenes |",
        "| --- | --- | ---: | ---: | ---: | :---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for t in atlas["tiles"]:
        lt = t["layers_triangles"]
        ext = ", ".join(Path(p).name for p in t["external_scenes"]) or "-"
        lines.append(
            f"| `{t['id']}` | `({t['origin_local_xz'][0]}, {t['origin_local_xz'][1]})` | {t['buildings']} | {t['total_triangles']:,} | {t['glb_disk_mb']} | "
            f"{'Yes' if t['has_sidewalks'] else 'No'} | {t['curb_m']:,.1f} | {t['crosswalks']} | {t['signals']} | "
            f"{lt.get('Bridges', 0):,} | {lt.get('ElevatedRoads', 0):,} | {ext} |"
        )

    lines += [
        "",
        "## 3. Poly Haven Library Summary",
        f"- **PBR Texture Sets**: `{len(atlas['polyhaven_inventory']['pbr_sets'])}` sets",
        f"- **Terrain3D Packed Slots**: `{len(atlas['polyhaven_inventory']['terrain_packed'])}` files",
        f"- **HDRIs**: `{len(atlas['polyhaven_inventory']['hdris'])}` (`{', '.join(h['id'] for h in atlas['polyhaven_inventory']['hdris'])}`)",
        "",
        "| Texture ID | Res | Maps | Path |",
        "| --- | :---: | ---: | --- |",
    ]
    for s in atlas["polyhaven_inventory"]["pbr_sets"]:
        lines.append(f"| `{s['id']}` | {s['resolution']} | {s['map_count']} | `{s['path']}` |")

    lines += [
        "",
        "## 4. Target Harlingen Landmarks & Geographic Sites",
        "",
        "| Category | Matches | Sample Tiles / Notes |",
        "| --- | ---: | --- |",
    ]
    for k, hits in sorted(atlas["harlingen_landmarks"]["target_landmark_hits"].items()):
        tiles = ", ".join(sorted({h["tile"] for h in hits})) or "-"
        lines.append(f"| `{k}` | {len(hits)} | {tiles} |")

    lines += [
        "",
        "## 5. Citywide Detailing Systems & Worker Ownership",
        "",
        "| Role / Module | Agent | Script / Class | Owned Paths |",
        "| --- | --- | --- | --- |",
    ]
    for key, info in atlas.get("citywide_detailing_systems", {}).items():
        script = info.get("script") or "-"
        owns = ", ".join(f"`{p}`" for p in info.get("owns", []))
        lines.append(f"| `{key}` | `{info.get('agent', '-')}` | `{script}` | {owns} |")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Harlingen Development Atlas (JSON + Markdown).")
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT, help="Path to Harlingen Godot project root")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="Output directory for atlas files")
    args = parser.parse_args()

    atlas = build_atlas(args.project)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    json_path = args.out_dir / "HARLINGEN_ATLAS.json"
    md_path = args.out_dir / "HARLINGEN_DEVELOPMENT_ATLAS.md"
    json_path.write_text(json.dumps(atlas, indent=2), encoding="utf-8")
    md_path.write_text(render_markdown(atlas), encoding="utf-8")
    print(f"Wrote {json_path} ({json_path.stat().st_size} bytes)")
    print(f"Wrote {md_path} ({md_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
