"""Build a north-up navigation atlas from the playable project's existing GIS data."""
import gzip
import json
from pathlib import Path

from PIL import Image, ImageDraw
from shapely.geometry import LineString, Point, shape

ROOT = Path(__file__).resolve().parents[1]
SIZE = 4096
BG = "#152326"
ROAD_STYLES = {
    "service": (0, 1, "#2a3c40"),
    "residential": (1, 2, "#486065"),
    "tertiary": (2, 3, "#6d8488"),
    "secondary": (3, 3, "#8b9da1"),
    "primary": (4, 4, "#aabaa9"),
    "trunk": (5, 5, "#c3b486"),
    "motorway_link": (6, 3, "#dcc189"),
    "motorway": (7, 5, "#e5c180"),
}
LANDMARK_IDS = {
    "osm:relation:8486141", "osm:way:204281585", "osm:way:690635467",
    "osm:way:1196397348", "osm:way:152478473", "osm:way:224682707",
    "osm:way:473594612", "osm:way:545113289", "city:parcel:9401",
    "osm:way:498375780", "city:campus:mma", "city:campus:tstc", "thc:iwo-jima",
}
BRIDGE_LABELS = [
    ("i2", "I-2 / US 83", "97348008", "Elevated mainline · west approach"),
    ("i69", "I-69E / US 77", "97347912", "Elevated mainline · downtown bypass"),
    ("flyover", "Big Split upper flyover", "97348013", "Upper deck · I-2 / I-69E"),
    ("ed-bridge", "Ed Carey · Arroyo overpass", "567766739", "Loop 499 bridge · Hugh Ramsey Nature Park"),
]
CROSSING_LABELS = [
    ("big-split", "I-2 / I-69E interchange", "97348034", "143685397", "Big Split · west-to-east flyover"),
    ("west-ramps", "West I-2 interchange ramps", "97347944", "569136402", "Elevated connector · west of Big Split"),
    ("south-ramps", "South I-69E interchange ramps", "97348004", "174532927", "Layer 2 overpass · south bypass"),
    ("south-overpass", "I-69E south overpass", "97348021", "119748999", "Elevated mainline · southern slip-road crossing"),
]


def lines(geom):
    if geom.geom_type == "LineString":
        yield geom
    elif hasattr(geom, "geoms"):
        for part in geom.geoms:
            yield from lines(part)


def polygons(geom):
    if geom.geom_type == "Polygon":
        yield geom
    elif hasattr(geom, "geoms"):
        for part in geom.geoms:
            yield from polygons(part)


def main():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    bounds = manifest["local_extent"]
    x0, z0, x1, z1 = bounds
    with gzip.open(ROOT / "source/osm_local.geojson.gz", "rt") as data:
        features = json.load(data)["features"]
    mapped = {f["id"]: (shape(f["geometry"]), f["properties"]) for f in features}
    image = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(image)

    def pixels(coords):
        return [((x - x0) / (x1 - x0) * SIZE, (z - z0) / (z1 - z0) * SIZE)
                for x, z in coords]

    for category, tags, color in (
        ("land", {"park", "recreation_ground", "nature_reserve", "grass", "wood", "forest", "golf_course"}, "#243b37"),
        ("land", {"water", "reservoir", "basin", "pond", "lake", "riverbank"}, "#1b4c59"),
        ("airstrip", {"aerodrome"}, "#293d3d"),
    ):
        for geom, props in mapped.values():
            if props["kind"] != category or not (tags & set(props.values())):
                continue
            for poly in polygons(geom):
                draw.polygon(pixels(poly.exterior.coords), fill=color)
                for hole in poly.interiors:
                    draw.polygon(pixels(hole.coords), fill=BG)

    for geom, props in mapped.values():
        if props["kind"] == "channel":
            for line in lines(geom):
                draw.line(pixels(line.coords), fill="#2f6574",
                          width=5 if props.get("waterway") == "river" else 2)

    # The FAA-audited pavement centerlines supersede the original OSM runway ends.
    for runway in manifest["airport_geography"]["runways"].values():
        draw.line(pixels(runway["endpoints_local_m"]), fill="#718990", width=10)

    roads = []
    for geom, props in mapped.values():
        if props["kind"] != "road":
            continue
        name = props.get("highway", "")
        if name != "motorway_link":
            name = name.removesuffix("_link")
        name = {"unclassified": "residential", "living_street": "residential"}.get(name, name)
        if name in ROAD_STYLES:
            roads.append((ROAD_STYLES[name], geom))
    for (order, width, color), geom in sorted(roads, key=lambda road: road[0][0]):
        for line in lines(geom):
            path = pixels(line.coords)
            if order >= 2:
                draw.line(path, fill="#122022", width=width + 2, joint="curve")
            draw.line(path, fill=color, width=width, joint="curve")

    markers = []

    def add(key, label, category, point, source, detail="", deck=None):
        x, z = point
        if not (x0 <= x <= x1 and z0 <= z <= z1):
            raise ValueError(f"{key} outside playable extent")
        row = dict(id=key, label=label, category=category, x=round(x, 3), z=round(z, 3),
                   source=source, detail=detail)
        if deck is not None:
            row["deck_y"] = deck
        markers.append(row)

    audit = manifest["elevated_highway"]
    included = set(audit["upgraded_osm_ways"])
    for key, label, way, detail in BRIDGE_LABELS:
        source = f"osm:way:{way}"
        line, props = mapped[source]
        if way not in included or not props.get("bridge"):
            raise ValueError(f"{label} is no longer a modeled bridge")
        add(key, label, "highway", line.interpolate(.5, normalized=True).coords[0], source, detail)

    audit_crossings = {(row["upper_way"], row["lower_way"]): row["center"]
                       for row in audit["bridge_clearance"]["crossings"]}
    for key, label, upper, lower, detail in CROSSING_LABELS:
        x, _, z, deck = audit_crossings[upper, lower]
        add(key, label, "highway", (x, z), f"osm:way:{upper}", detail, deck)

    for key, label, name, hint in (
        ("jackson", "Jackson Street", "West Jackson Avenue", (205, 316)),
        ("ed-carey", "Ed Carey Drive", "North Ed Carey Drive", (3025, 1668)),
    ):
        p = Point(hint)
        line, source = min(((g, i) for i, (g, t) in mapped.items()
                            if t.get("kind") == "road" and t.get("name") == name
                            and g.geom_type == "LineString"), key=lambda row: row[0].distance(p))
        if line.distance(p) > 10:
            raise ValueError(f"{label} seed no longer aligns with the mapped road")
        add(key, label, "street", line.interpolate(line.project(p)).coords[0], source, name)

    found = {row["source"]: row for row in manifest["landmarks"]
             if row["source"] in LANDMARK_IDS}
    if found.keys() != LANDMARK_IDS:
        raise ValueError(f"Missing landmarks: {LANDMARK_IDS - found.keys()}")
    for key, row in sorted(found.items(), key=lambda pair: pair[1]["name"]):
        add(key, row["name"], "landmark", (row["x"], row["z"]), key)

    out = ROOT / "assets/navigation"
    out.mkdir(exist_ok=True)
    image.save(out / "harlingen_map.png", optimize=True)
    (out / "map_index.json").write_text(json.dumps(dict(
        bounds=bounds, markers=markers, road_ways=len(roads), origin_epsg=manifest["origin_epsg"],
        origin_easting=manifest["origin_easting"], origin_northing=manifest["origin_northing"],
    ), indent=2) + "\n")


if __name__ == "__main__":
    main()
