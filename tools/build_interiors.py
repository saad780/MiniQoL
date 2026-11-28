"""Regenerate src/Modules/Wayfinder/Data/Interiors.lua from the client's own files.

Indoors, the corner minimap stops drawing terrain and draws a small picture of
each room of the building you're in. Those pictures are listed in the
WMOMinimapTexture table: per building model (WMOID), per room (group number),
per 256-pixel block, one texture FileDataID. This script finds every building
standing on Forever's continents and works out where each picture goes, so the
indoor view can draw the rooms around the player without asking the game for
anything but the player's position.

Sources, all from the client of the build below:
  * each continent's WDT: its MAID chunk names every map tile's obj0 file;
  * obj0 files: MODF lists the buildings (WMO roots) placed on the tile, with
    position, rotation and scale;
  * WMO root files: MOHD (the model's WMOID and bounding box), MOGI (each
    room's flags and bounding box), MOPT/MOPV/MOPR (portals between rooms);
  * WMOMinimapTexture (DB2, as CSV): the pictures;
  * the pictures themselves (BLP), to check that each one belongs to its room
    and to learn where the room's floor is drawn;
  * WMO group files (MOVT, MOVI, MPY2/MOPY: walkable collision triangles), for
    the rooms of places with more than one floor, to trace their staircases.

Rooms, places and floors:
  * Only indoor rooms (MOGI flag 0x2000) with pictures are kept.
  * Rooms joined by portals are a place (a house, a cave). Rooms lit as
    outdoors (flag 0x40: porches, arches, a city's streets inside its model)
    don't join the others, and a portal into one counts as a door outside.
  * A place's floors: its rooms grouped by the height of their lowest point
    (3 yards apart); neighbouring heights where no room stands over another
    are one floor (a sloping cave). G is the lowest floor with a door outside.
  * Staircases: walkable surfaces between two floors, reached from both by
    steps of at most 0.75 yards; per 2-yard square, how far up it is.

What the files show (checked against renders of known buildings):
  * Pictures are 2 pixels per yard. A room's picture is cut into blocks of
    256 pixels (128 yards); block (x, y) starts x * 128 yards along the room's
    own x axis and y * 128 along its y axis from its bounding box's minimum.
  * Within a block, the drawing is in the picture's bottom-left corner:
    picture right is the room's +x and picture up its +y. The picture's size
    is a power of two, so it may be larger than what is drawn in it.
  * Some rows are stale: they name blocks a room is too small to have, or a
    picture the wrong size for its room (left over from an older model). Those
    are found by comparing the drawing with the room's bounding box, and left out.
  * Placement (MODF): world north = 17066.67 - position z, world west =
    17066.67 - position x (yards, as UnitPosition gives them). A point (a, b)
    in the model's own yards, turned by the yaw r (rotation y, degrees), is at
        north = N0 - (a cos r - b sin r) * scale
        west  = W0 - (a sin r + b cos r) * scale
    Every placement's MODF extents are checked against this (they agree to a
    fraction of a yard, a few models' boxes by up to 5 on one side), and
    buildings leaning more than 5 degrees are left out.

Usage:
    python tools/build_interiors.py                  # the build below
    python tools/build_interiors.py --build 1.60.2.x # after a client patch
    python tools/build_interiors.py --only 7952345 --output somewhere.lua  # a few models

Files are fetched from wago.tools and cached in tools/.cache/ (about 9,000
files on the first run, an hour or two at the polite pace below; later runs
read the cache and take a few minutes).
"""
from __future__ import annotations

import argparse
import csv
import io
import math
import os
import re
import struct
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BUILD = "1.60.1.71139"  # WoW: Forever (wago.tools product "wowf")

# instance (continent) ID -> WDT FileDataID
MAPS = {
    0: 775971,     # Eastern Kingdoms
    1: 782779,     # Kalimdor
    2991: 7198644,  # Zephras Isle
    2997: 7251908,  # Darkspear Islands
}

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "tools" / ".cache"
OUT = ROOT / "src" / "Modules" / "Wayfinder" / "Data" / "Interiors.lua"
USER_AGENT = "MiniQoL-build-interiors (offline data generator)"

TILE = 1600 / 3
ORIGIN = 32 * TILE      # placement coordinates count from the map's corner
PIXELS_PER_YARD = 2
BLOCK = 256             # pixels in a full picture block
CELL = 2                # yards per square of a room's footprint
INTERIOR = 0x2000       # MOGI flag: an indoor room
EXTERIOR_LIT = 0x40     # ... lit as outdoors: a porch, an arch, a city street under the model
UNREACHABLE = 0x80
ANTIPORTAL = 0x4000000
FLOOR_GAP = 3.0         # yards between two floors' lowest points
OVERLAP_CELLS = 3       # footprint squares two rooms must share to stack


# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------
_lock = threading.Lock()
_last_request = [0.0]
# Seconds between requests, across all workers. wago.tools answers 429 with a
# Retry-After when asked too often: then this widens, and narrows again slowly.
_spacing = [0.25]


def fetch(fdid, build):
    folder = CACHE / "casc"
    path = folder / f"{fdid}-{build}"
    if path.exists():
        return path.read_bytes()
    folder.mkdir(parents=True, exist_ok=True)
    url = f"https://wago.tools/api/casc/{fdid}?version={build}"
    failures = 0
    while True:
        with _lock:
            wait = _spacing[0] - (time.time() - _last_request[0])
            if wait > 0:
                time.sleep(wait)
            _last_request[0] = time.time()
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=90) as response:
                data = response.read()
            with _lock:
                _spacing[0] = max(0.25, _spacing[0] * 0.97)
            break
        except urllib.error.HTTPError as error:
            if error.code != 429:
                failures += 1
                if failures >= 5:
                    raise
                time.sleep(3 * failures)
                continue
            try:
                retry = float(error.headers.get("Retry-After") or 5)
            except ValueError:
                retry = 5
            with _lock:
                _spacing[0] = min(3.0, _spacing[0] * 1.5)
                _last_request[0] = time.time() + retry
        except Exception:
            failures += 1
            if failures >= 5:
                raise
            time.sleep(3 * failures)
    temporary = path.with_suffix(f".part{threading.get_ident()}")
    temporary.write_bytes(data)
    os.replace(temporary, path)
    return data


def fetch_all(fdids, build, workers, label):
    fdids = sorted(set(fdids))
    missing = [f for f in fdids if not (CACHE / "casc" / f"{f}-{build}").exists()]
    if missing:
        print(f"{label}: fetching {len(missing)} of {len(fdids)} files", flush=True)
        done = [0]

        def one(fdid):
            fetch(fdid, build)
            with _lock:
                done[0] += 1
                if done[0] % 200 == 0:
                    print(f"  {done[0]}/{len(missing)}", flush=True)

        with ThreadPoolExecutor(workers) as pool:
            list(pool.map(one, missing))
    return {f: fetch(f, build) for f in fdids}


def table(name, build):
    path = CACHE / f"{name}-{build}.csv"
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        url = f"https://wago.tools/db2/{name}/csv?build={build}"
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=180) as response:
            path.write_bytes(response.read())
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


# ---------------------------------------------------------------------------
# File formats
# ---------------------------------------------------------------------------
def chunks(data):
    pos = 0
    while pos + 8 <= len(data):
        magic = data[pos:pos + 4][::-1].decode("ascii", "replace")  # stored reversed
        size = struct.unpack_from("<I", data, pos + 4)[0]
        yield magic, data[pos + 8:pos + 8 + size]
        pos += 8 + size


def chunk(data, name):
    for magic, body in chunks(data):
        if magic == name:
            return body
    return None


def obj0_files(wdt):
    """(column, row) -> obj0 FileDataID, from the WDT's MAID chunk."""
    body = chunk(wdt, "MAID")
    if not body or len(body) != 64 * 64 * 32:
        raise ValueError("WDT has no 64x64 MAID chunk")
    tiles = {}
    for index in range(64 * 64):
        root, obj0 = struct.unpack_from("<2I", body, index * 32)
        if root and obj0:
            row, col = divmod(index, 64)  # MAID index = row * 64 + col
            tiles[(col, row)] = obj0
    return tiles


def placements(obj0):
    body = chunk(obj0, "MODF") or b""
    for index in range(len(body) // 64):
        v = struct.unpack_from("<2I3f3f6f4H", body, index * 64)
        yield dict(file=v[0], uid=v[1], pos=v[2:5], rot=v[5:8], lo=v[8:11], hi=v[11:14],
                   flags=v[14], scale=(v[17] / 1024) if v[14] & 0x4 else 1.0)


def read_root(data):
    mohd = chunk(data, "MOHD")
    header = struct.unpack_from("<7I4BI6f", mohd, 0)
    model = dict(wmo_id=header[11], lo=header[12:15], hi=header[15:18], groups=[], portals=[])
    mogi = chunk(data, "MOGI") or b""
    for index in range(len(mogi) // 32):
        g = struct.unpack_from("<I6fi", mogi, index * 32)
        model["groups"].append(dict(flags=g[0], lo=g[1:4], hi=g[4:7]))
    # Each portal is listed twice in MOPR, once from the room on either side,
    # each time naming the room on the other side.
    mopt, mopv, mopr = chunk(data, "MOPT") or b"", chunk(data, "MOPV") or b"", chunk(data, "MOPR") or b""
    sides = defaultdict(list)
    for index in range(len(mopr) // 8):
        portal, group, _side, _ = struct.unpack_from("<HHhH", mopr, index * 8)
        sides[portal].append(group)
    for portal in range(len(mopt) // 20):
        start, count = struct.unpack_from("<HH", mopt, portal * 20)
        zs = [struct.unpack_from("<3f", mopv, (start + k) * 12)[2] for k in range(count)]
        model["portals"].append((tuple(sides.get(portal, ())), min(zs, default=0), max(zs, default=0)))
    gfid = chunk(data, "GFID") or b""
    model["group_files"] = list(struct.unpack_from(f"<{len(gfid) // 4}I", gfid)) if gfid else []
    return model


def read_picture(data):
    from PIL import Image
    return Image.open(io.BytesIO(data)).convert("RGBA")


def read_walkable(data):
    """The walkable collision triangles of a WMO group file, in the model's yards."""
    mogp = chunk(data, "MOGP")
    if not mogp:
        return []
    sub = dict(chunks(mogp[0x44:]))
    movt, movi = sub.get("MOVT", b""), sub.get("MOVI", b"")
    vertices = [struct.unpack_from("<3f", movt, i * 12) for i in range(len(movt) // 12)]
    indices = struct.unpack_from(f"<{len(movi) // 2}H", movi) if movi else ()
    # Per triangle flags: MPY2 (newer files, 4 bytes each) or MOPY (2 bytes).
    # A triangle stops you if it is collision geometry (0x08), or drawn (0x20)
    # without being a detail (0x04).
    if "MPY2" in sub:
        flags = [struct.unpack_from("<H", sub["MPY2"], i * 4)[0] for i in range(len(sub["MPY2"]) // 4)]
    else:
        flags = list(sub.get("MOPY", b"")[0::2])
    walkable = []
    for face in range(len(indices) // 3):
        flag = flags[face] if face < len(flags) else 0
        if not (flag & 0x08 or (flag & 0x20 and not flag & 0x04)):
            continue
        a, b, c = (vertices[indices[face * 3 + k]] for k in range(3))
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        # Facing up (the winding agrees with MONR's normals), flatter than about 53 degrees.
        if length > 0 and nz / length >= 0.6:
            walkable.append((a, b, c))
    return walkable


# ---------------------------------------------------------------------------
# Placement transform
# ---------------------------------------------------------------------------
def to_world(place, a, b):
    """A point in the model's own yards -> world (north, west)."""
    r = math.radians(place["rot"][1])
    s = place["scale"]
    north0, west0 = ORIGIN - place["pos"][2], ORIGIN - place["pos"][0]
    return (north0 - (a * math.cos(r) - b * math.sin(r)) * s,
            west0 - (a * math.sin(r) + b * math.cos(r)) * s)


def extents_match(place, model):
    """Whether the model's box, placed by to_world, gives MODF's own extents."""
    lo, hi = model["lo"], model["hi"]
    norths, wests = [], []
    for a in (lo[0], hi[0]):
        for b in (lo[1], hi[1]):
            n, w = to_world(place, a, b)
            norths.append(n)
            wests.append(w)
    # MODF extents are in placement coordinates: x = ORIGIN - west, z = ORIGIN - north
    want_x = (place["lo"][0], place["hi"][0])
    want_z = (place["lo"][2], place["hi"][2])
    got_x = (ORIGIN - max(wests), ORIGIN - min(wests))
    got_z = (ORIGIN - max(norths), ORIGIN - min(norths))
    # Nearly all agree to a fraction of a yard; a few models' boxes have
    # since grown or shrunk on one side by a few yards.
    return all(abs(g - w) < 5 for g, w in zip(got_x + got_z, want_x + want_z))


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------
def check_picture(image, size, bx, by):
    """Whether a picture can be block (bx, by) of a room `size` pixels across.

    The drawing must fit in the part of the block the room reaches, from the
    picture's bottom-left corner, and the picture must be big enough for it."""
    width, height = image.size
    reach_x = min(BLOCK, size[0] - BLOCK * bx)
    reach_y = min(BLOCK, size[1] - BLOCK * by)
    if reach_x <= 0 or reach_y <= 0:
        return "block outside the room"
    if width < reach_x - 3 or height < reach_y - 3:
        return "picture smaller than the room"
    box = image.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if box is None:
        return "empty"
    if box[2] > reach_x + 4 or box[1] < height - reach_y - 4:
        return "drawing larger than the room"
    return None


def footprint(group, pictures):
    """The room's floor plan: squares of CELL yards over its bounding box, set
    where the pictures draw something. Returns (columns, rows, set of (i, j))."""
    lo, hi = group["lo"], group["hi"]
    columns = max(1, math.ceil((hi[0] - lo[0]) / CELL))
    rows = max(1, math.ceil((hi[1] - lo[1]) / CELL))
    counts = defaultdict(int)
    for (bx, by), image in pictures.items():
        alpha = image.getchannel("A").load()
        width, height = image.size
        for py in range(height):
            b = BLOCK * by + (height - py - 0.5)  # pixels up from the room's minimum y
            j = int(b / PIXELS_PER_YARD // CELL)
            if j >= rows:
                continue
            for px in range(width):
                if alpha[px, py] > 128:
                    i = int((BLOCK * bx + px + 0.5) / PIXELS_PER_YARD // CELL)
                    if i < columns:
                        counts[(i, j)] += 1
    full = (CELL * PIXELS_PER_YARD) ** 2
    return columns, rows, {cell for cell, n in counts.items() if n * 4 >= full}


def model_cells(room):
    """A room's footprint squares on a grid shared by the whole model."""
    lo = room["lo"]
    return {(math.floor((lo[0] + CELL * (i + 0.5)) / CELL), math.floor((lo[1] + CELL * (j + 0.5)) / CELL))
            for i, j in room["cells"]}


def lit_outside(info):
    return bool(info["flags"] & EXTERIOR_LIT)


def places_of(model, rooms):
    """Rooms that open into one another (through indoor rooms, pictured or not)
    are one place: a house, a cave. Rooms lit as outdoors (a city's streets
    and squares can be indoor rooms of one huge model) don't join a building's
    rooms: they are outside it. Returns place index per room number, and the
    portal links (all indoor ones, for neighbours)."""
    groups = model["groups"]
    indoor = {g for g, info in enumerate(groups) if info["flags"] & INTERIOR}
    links, joins = defaultdict(set), defaultdict(set)
    for sides, _, _ in model["portals"]:
        if len(sides) == 2 and sides[0] in indoor and sides[1] in indoor:
            a, b = sides
            links[a].add(b)
            links[b].add(a)
            if lit_outside(groups[a]) == lit_outside(groups[b]):
                joins[a].add(b)
                joins[b].add(a)
    place, count = {}, 0
    for start in sorted(rooms):
        if start in place:
            continue
        stack = [start]
        place[start] = count
        while stack:
            g = stack.pop()
            for n in joins[g]:
                if n not in place:
                    place[n] = count
                    stack.append(n)
        count += 1
    return {g: place[g] for g in rooms}, links


def neighbours(rooms, links):
    """Pictured rooms reachable from each pictured room through portals,
    passing through unpictured indoor rooms on the way."""
    result = {}
    for start in rooms:
        seen, stack, found = {start}, [start], set()
        while stack:
            g = stack.pop()
            for n in links[g]:
                if n in seen:
                    continue
                seen.add(n)
                if n in rooms:
                    found.add(n)
                else:
                    stack.append(n)
        result[start] = sorted(found)
    return result


def entrances(model, rooms):
    """Indoor rooms with a door to the outside: a portal to an outdoor room
    (or one lit as outdoors, from a room that isn't), or to nothing (the terrain)."""
    groups = model["groups"]

    def outside(g, other):
        info = groups[other]
        return not info["flags"] & INTERIOR or (lit_outside(info) and not lit_outside(groups[g]))

    result = set()
    for sides, _, _ in model["portals"]:
        if len(sides) == 1 and sides[0] in rooms:
            result.add(sides[0])
        elif len(sides) == 2 and max(sides) < len(groups):
            a, b = sides
            if a in rooms and outside(a, b):
                result.add(a)
            if b in rooms and outside(b, a):
                result.add(b)
    return result


def floors_of(model, rooms, place_of):
    """Each place's floors. Rooms are grouped by the height of their lowest
    point; two neighbouring heights are one floor unless rooms of the two
    stand over one another. Returns {place: [floor, ...]} bottom up, each floor
    {"rooms", "z"(lowest point), "label"}, and sets room["floor"]."""
    doors = entrances(model, rooms)
    for g, room in rooms.items():
        room["door"] = g in doors
    result = {}
    for place in sorted(set(place_of.values())):
        members = sorted((g for g in rooms if place_of[g] == place), key=lambda g: rooms[g]["lo"][2])
        # Measured from each height's lowest room, so that landings a couple of
        # yards apart don't chain one storey into the next.
        levels = []
        for g in members:
            z = rooms[g]["lo"][2]
            if levels and z - levels[-1]["z"] < FLOOR_GAP:
                levels[-1]["rooms"].append(g)
                levels[-1]["top"] = z
            else:
                levels.append({"rooms": [g], "z": z, "top": z})
        # Heights with nothing over one another are one floor (a sloping cave).
        floors = []
        for level in levels:
            cells = set().union(*(rooms[g]["model_cells"] for g in level["rooms"]))
            if floors and len(cells & floors[-1]["cells"]) < OVERLAP_CELLS:
                floors[-1]["rooms"] += level["rooms"]
                floors[-1]["cells"] |= cells
                floors[-1]["top"] = level["top"]
            else:
                floors.append({"rooms": list(level["rooms"]), "cells": cells, "z": level["z"], "top": level["top"]})
        ground = None
        for index, floor in enumerate(floors):
            if any(g in doors for g in floor["rooms"]):
                ground = index
                break
        for index, floor in enumerate(floors):
            if ground is None:
                floor["label"] = str(index + 1)
            elif index == ground:
                floor["label"] = "G"
            elif index > ground:
                floor["label"] = str(index - ground + 1)
            else:
                below = ground - index
                floor["label"] = "B" if ground == 1 else f"B{below}"
            for g in floor["rooms"]:
                rooms[g]["floor"] = index
        result[place] = {"floors": floors, "ground": ground}
    return result


def shown_on(rooms, place_of, layout):
    """Floors each room is drawn on: its own, and higher ones it is open to (a
    hall with a gallery). Also floors where it is drawn faintly: all the
    others, if no room of another floor stands over or under it, so a cave
    whose levels mostly don't stack shows whole, while a house shows one storey."""
    for g, room in rooms.items():
        floors = layout[place_of[g]]["floors"]
        own = room["floor"]
        shown = 1 << own
        for index, floor in enumerate(floors):
            if index > own and room["hi"][2] >= floor["z"] + FLOOR_GAP:
                shown |= 1 << index
        stacked = any(o != g and place_of[o] == place_of[g] and other["floor"] != own
                      and len(room["model_cells"] & other["model_cells"]) >= OVERLAP_CELLS
                      for o, other in rooms.items())
        faint = 0 if stacked else ((1 << len(floors)) - 1) & ~shown
        room["shown"], room["faint"] = shown, faint


# ---------------------------------------------------------------------------
# Staircases
# ---------------------------------------------------------------------------
STEP = 0.5        # yards per square when tracing walkable surfaces
CLIMB = 0.75      # the most a surface can rise to the next square and still be walked up
ON_FLOOR = 0.7    # a surface this close to a floor's height is that floor
STAIR_CELL = 2    # yards per square of a staircase in the output
STAIR_MOST = 2000 # square yards: bigger "staircases" are the sloping floors of big halls and caves


def surfaces(triangles):
    """Walkable heights over a grid of STEP-yard squares: {(i, j): [z, ...]},
    one height per surface through the square's middle."""
    found = defaultdict(list)
    for a, b, c in triangles:
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-9:
            continue
        i0 = math.floor(min(a[0], b[0], c[0]) / STEP)
        i1 = math.floor(max(a[0], b[0], c[0]) / STEP)
        j0 = math.floor(min(a[1], b[1], c[1]) / STEP)
        j1 = math.floor(max(a[1], b[1], c[1]) / STEP)
        for i in range(i0, i1 + 1):
            x = (i + 0.5) * STEP
            for j in range(j0, j1 + 1):
                y = (j + 0.5) * STEP
                l1 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / d
                l2 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / d
                l3 = 1 - l1 - l2
                if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
                    found[(i, j)].append(l1 * a[2] + l2 * b[2] + l3 * c[2])
    result = {}
    for cell, zs in found.items():
        zs.sort()
        kept = [zs[0]]
        for z in zs[1:]:
            if z - kept[-1] > 0.2:
                kept.append(z)
        result[cell] = kept
    return result


def floor_heights(heights, guesses):
    """Each floor's walking height: the commonest surface height near the
    lowest point of its rooms (a floor's rooms reach a little below it)."""
    counts = defaultdict(int)
    for zs in heights.values():
        for z in zs:
            counts[round(z * 4) / 4] += 1
    result = []
    for guess in guesses:
        near = [(n, z) for z, n in counts.items() if guess - 0.5 <= z <= guess + 1.5]
        result.append(max(near)[1] if near else guess)
    return result


def staircases(heights, levels):
    """Walkable surfaces between two neighbouring floors that can be walked to
    from both. Returns [(low floor, high floor, {(i, j): fraction up})]."""
    # Every surface: which floor it is on, if any.
    nodes = {}
    for cell, zs in heights.items():
        for k, z in enumerate(zs):
            on = None
            for f, level in enumerate(levels):
                if abs(z - level) <= ON_FLOOR:
                    on = f
                    break
            nodes[(cell, k)] = on

    def neighbours(node):
        (i, j), k = node
        z = heights[(i, j)][k]
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                if di or dj:
                    other = heights.get((i + di, j + dj))
                    if other:
                        for m, w in enumerate(other):
                            if abs(w - z) <= CLIMB:
                                yield (i + di, j + dj), m

    # Flood from each floor's surfaces across surfaces between floors.
    reached = defaultdict(set)
    for f in range(len(levels)):
        stack = [n for n, on in nodes.items() if on == f]
        seen = set(stack)
        while stack:
            node = stack.pop()
            for n in neighbours(node):
                if n not in seen and nodes[n] is None:
                    seen.add(n)
                    reached[n].add(f)
                    stack.append(n)
    result = []
    for low in range(len(levels) - 1):
        high = low + 1
        span = levels[high] - levels[low]
        cells = {}
        for node, floors in reached.items():
            if low in floors and high in floors:
                z = heights[node[0]][node[1]]
                if levels[low] < z < levels[high]:
                    cells[node] = (z - levels[low]) / span
        # One staircase per connected run of such surfaces.
        while cells:
            start = next(iter(cells))
            run, stack = {start: cells.pop(start)}, [start]
            while stack:
                for n in neighbours(stack.pop()):
                    if n in cells:
                        run[n] = cells.pop(n)
                        stack.append(n)
            ups = list(run.values())
            # A real staircase climbs most of the way; a ledge or a bump doesn't.
            # A huge one is the sloping floor of a cave or a city's hall: the
            # rooms you walk into tell its floors apart well enough, and its
            # squares would be most of the data.
            area = len(run) * STEP * STEP
            if len(run) >= 6 and max(ups) - min(ups) >= 0.5 and area <= STAIR_MOST:
                result.append((low, high, {node[0]: t for node, t in run.items()}))
    return result


def pack_stair(place, low, high, squares):
    """A staircase on STAIR_CELL-yard squares: place, floors (from 1), corner,
    size, and per square how far up it is, "0"-"9" (tenths); a run of squares
    with none is a letter, "a" for one to "z" for 26."""
    merged = defaultdict(list)
    ratio = STAIR_CELL / STEP
    for (i, j), t in squares.items():
        merged[(math.floor(i / ratio), math.floor(j / ratio))].append(t)
    i0 = min(i for i, _ in merged)
    j0 = min(j for _, j in merged)
    columns = max(i for i, _ in merged) - i0 + 1
    rows = max(j for _, j in merged) - j0 + 1
    text = []
    for j in range(rows):
        for i in range(columns):
            ts = merged.get((i0 + i, j0 + j))
            # Where the staircase passes over itself (a spiral, or the foot of
            # one that turns back under its head), the square has no one
            # height: left blank. (Along a flight, a square spans less than
            # half its rise.)
            if ts and max(ts) - min(ts) <= 0.45:
                text.append(str(min(9, int(sum(ts) / len(ts) * 10))))
            else:
                text.append(".")

    def gap(match):
        n = len(match[0])
        return "z" * (n // 26) + (chr(96 + n % 26) if n % 26 else "")

    steps = re.sub(r"\.+", gap, "".join(text).rstrip("."))
    return "{" + ",".join([str(place + 1), str(low + 1), str(high + 1), number(i0 * STAIR_CELL),
                           number(j0 * STAIR_CELL), str(columns), str(rows), '"' + steps + '"']) + "}"


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"


def pack_bits(columns, rows, cells):
    """Footprint squares, row by row from the room's minimum, 6 to a character."""
    out, value, count = [], 0, 0
    for j in range(rows):
        for i in range(columns):
            if (i, j) in cells:
                value |= 1 << count
            count += 1
            if count == 6:
                out.append(ALPHABET[value])
                value, count = 0, 0
    if count:
        out.append(ALPHABET[value])
    return "".join(out).rstrip("0")


def number(value, places=1):
    text = f"{value:.{places}f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def write_lua(path, build, models, placed, stats):
    lines = [
        "-- GENERATED by tools/build_interiors.py from the client's own files. Do not edit by hand.",
        f"-- Client build: {build}",
        "--",
        "-- models[i]: one kind of building (WMO), in its own yards.",
        "--   [1] the floors of each place (rooms that open into one another), bottom up:",
        "--       labels separated by commas, places by \"|\". G is the lowest floor with a",
        "--       door to the outside; without one, floors are numbered from the bottom. (A",
        "--       city's district can be one place; the runtime labels floors near you.)",
        "--   [2], [3], ...: its rooms, each",
        "--       { x, y (its minimum corner), columns, rows (of its footprint squares,",
        "--         2 yards each), place, floor (in the place, from 1 at the bottom),",
        "--         floors it is drawn on (bit n-1 for floor n), floors it is drawn faint on,",
        "--         footprint (squares row by row from the corner, 6 bits to a character of",
        "--         0-9A-Za-z+/, lowest bit first, trailing zeros left off),",
        "--         { neighbouring rooms (through portals) }, 1 if it has a door to the outside,",
        "--         picture FileDataID, block, size, ... }",
        "--       block = x + 16 * y: the picture starts x * 128 yards along the room's x",
        "--       and y * 128 along its y from the corner. size = log2(width) + 16 *",
        "--       log2(height) in pixels, at 2 pixels a yard, drawn from the picture's",
        "--       bottom left: picture right is the room's +x, picture up its +y.",
        "--   stairs (optional): { place, floor at its foot, floor at its head, x, y (its",
        "--       corner), columns, rows (of stairCell-yard squares), how far up each square",
        "--       is in tenths, \"0\"-\"9\", row by row from the corner; a run of squares that",
        "--       aren't on it is a letter, \"a\" for one to \"z\" for 26 (trailing ones left off) }",
        "-- placed[continent]: model, north, west (yards, as UnitPosition gives them),",
        "--   yaw (degrees), scale, ... A point (a, b) of the model is at",
        "--   north = N - (a cos(yaw) - b sin(yaw)) * scale, west = W - (a sin(yaw) + b cos(yaw)) * scale.",
        "local _, ns = ...",
        "",
        "ns.InteriorData = {",
        f'\tbuild = "{build}",',
        f"\tstairCell = {STAIR_CELL}, -- yards per square of a staircase",
        "\tmodels = {",
    ]
    for model in models:
        parts = ["{" + '"' + model["floors"] + '"']
        for room in model["rooms"]:
            pics = []
            for fdid, bx, by, w, h in room["pictures"]:
                pics += [str(fdid), str(bx + 16 * by), str(int(math.log2(w)) + 16 * int(math.log2(h)))]
            parts.append("{" + ",".join([
                number(room["lo"][0]), number(room["lo"][1]), str(room["columns"]), str(room["rows"]),
                str(room["place"] + 1), str(room["floor"] + 1), str(room["shown"]), str(room["faint"]),
                '"' + room["bits"] + '"', "{" + ",".join(str(n) for n in room["neighbours"]) + "}",
                "1" if room.get("door") else "0",
            ] + pics) + "}")
        if model.get("stairs"):
            parts.append("stairs={" + ",".join(model["stairs"]) + "}")
        lines.append("\t\t" + ",".join(parts) + "}, -- " + model["comment"])
    lines.append("\t},")
    lines.append("\tplaced = {")
    for cont in sorted(placed):
        items = placed[cont]
        lines.append(f"\t\t[{cont}] = {{ -- {len(items)} buildings")
        for k in range(0, len(items), 6):
            lines.append("\t\t\t" + "".join(
                f"{m},{number(n)},{number(w)},{number(y, 2)},{number(s, 3)}," for m, n, w, y, s in items[k:k + 6]))
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {path} ({path.stat().st_size:,} bytes): " + ", ".join(f"{k} {v}" for k, v in stats.items()))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--build", default=BUILD)
    parser.add_argument("--workers", type=int, default=2, help="parallel downloads (be polite)")
    parser.add_argument("--output", type=Path, default=OUT)
    parser.add_argument("--no-stairs", action="store_true", help="skip the group files and staircases")
    parser.add_argument("--only", help="comma-separated model (WMO root) FileDataIDs, for checking a few buildings")
    args = parser.parse_args()
    build = args.build
    stats = {}

    # 1. Buildings placed on each continent, one entry per unique ID.
    by_cont = {}
    for cont, wdt in MAPS.items():
        tiles = obj0_files(fetch(wdt, build))
        files = fetch_all(tiles.values(), build, args.workers, f"continent {cont} tiles")
        found = {}
        for obj0 in files.values():
            for place in placements(obj0):
                found.setdefault(place["uid"], place)
        by_cont[cont] = list(found.values())
        print(f"continent {cont}: {len(tiles)} tiles, {len(found)} buildings placed", flush=True)
    named = sum(1 for places in by_cont.values() for p in places if not p["flags"] & 0x8)
    if named:
        print(f"warning: {named} placements name their model by file name, not FileDataID; skipped")

    # 2. Each model's root file: its WMOID, rooms and portals.
    root_ids = {p["file"] for places in by_cont.values() for p in places if p["flags"] & 0x8}
    if args.only:
        root_ids &= {int(f) for f in args.only.split(",")}
    roots = {fdid: read_root(data) for fdid, data in fetch_all(root_ids, build, args.workers, "models").items()}

    # 3. The pictures of each WMOID, by room and block.
    rows = defaultdict(lambda: defaultdict(dict))
    for row in table("WMOMinimapTexture", build):
        rows[int(row["WMOID"])][int(row["GroupNum"])][(int(row["BlockX"]), int(row["BlockY"]))] = int(row["FileDataID"])
    owners = defaultdict(list)
    for fdid, model in roots.items():
        owners[model["wmo_id"]].append(fdid)
    shared = {w: f for w, f in owners.items() if len(f) > 1 and w in rows}
    if shared:
        print(f"note: {len(shared)} WMOIDs are used by more than one model file; each is checked on its own")

    candidates = {}
    for fdid, model in roots.items():
        groups = rows.get(model["wmo_id"])
        if not groups:
            continue
        for g, blocks in groups.items():
            if g >= len(model["groups"]):
                continue
            info = model["groups"][g]
            if not info["flags"] & INTERIOR or info["flags"] & (UNREACHABLE | ANTIPORTAL):
                continue
            size = [(info["hi"][k] - info["lo"][k]) * PIXELS_PER_YARD for k in (0, 1)]
            for (bx, by), picture in blocks.items():
                if BLOCK * bx < size[0] and BLOCK * by < size[1]:
                    candidates.setdefault((fdid, g), {})[(bx, by)] = picture
    picture_ids = {p for blocks in candidates.values() for p in blocks.values()}
    print(f"{len(candidates)} indoor rooms with pictures in {len({f for f, _ in candidates})} models; "
          f"{len(picture_ids)} pictures", flush=True)
    images = {f: read_picture(d) for f, d in fetch_all(picture_ids, build, args.workers, "pictures").items()}

    # 4. Check each room's pictures and read its footprint from them.
    rejected = defaultdict(int)
    models = {}
    for (fdid, g), blocks in sorted(candidates.items()):
        info = roots[fdid]["groups"][g]
        size = [(info["hi"][k] - info["lo"][k]) * PIXELS_PER_YARD for k in (0, 1)]
        good = {}
        problem = None
        for block, picture in blocks.items():
            problem = check_picture(images[picture], size, *block)
            if problem == "empty":
                continue
            if problem:
                break
            good[block] = picture
        if problem and problem != "empty":
            rejected[problem] += 1
            continue  # one wrong block: the room's pictures can't be trusted
        if not good:
            rejected["empty"] += 1
            continue
        columns, rows_, cells = footprint(info, {b: images[p] for b, p in good.items()})
        if not cells:
            rejected["no floor drawn"] += 1
            continue
        room = dict(lo=info["lo"], hi=info["hi"], columns=columns, rows=rows_, cells=cells,
                    pictures=[(p, bx, by) + images[p].size for (bx, by), p in sorted(good.items())])
        room["model_cells"] = model_cells(room)
        models.setdefault(fdid, {})[g] = room
    stats["rooms"] = sum(len(r) for r in models.values())
    print("rooms left out: " + ", ".join(f"{k} {v}" for k, v in sorted(rejected.items())), flush=True)

    # 5. Places, floors and neighbours.
    for fdid, rooms in models.items():
        model = roots[fdid]
        place_of, links = places_of(model, rooms)
        layout = floors_of(model, rooms, place_of)
        shown_on(rooms, place_of, layout)
        near = neighbours(rooms, links)
        for g, room in rooms.items():
            room["place"] = place_of[g]
            room["near"] = near[g]
        model["layout"] = layout

    # 6. Staircases, in places with more than one floor: from the walkable
    # surfaces of every room of the place, in the building's own yards.
    if not args.no_stairs:
        wanted = {}
        for fdid, rooms in models.items():
            model = roots[fdid]
            for place, layout in model["layout"].items():
                if len(layout["floors"]) < 2:
                    continue
                for g, room in rooms.items():
                    if room["place"] == place and g < len(model["group_files"]) and model["group_files"][g]:
                        wanted[model["group_files"][g]] = (fdid, place, g)
        print(f"staircases: {len(wanted)} room files in places with several floors", flush=True)
        files = fetch_all(wanted, build, args.workers, "room files")
        walkable = defaultdict(list)
        for file, (fdid, place, g) in wanted.items():
            walkable[(fdid, place)] += read_walkable(files[file])
        count = 0
        for (fdid, place), triangles in sorted(walkable.items()):
            layout = roots[fdid]["layout"][place]
            heights = surfaces(triangles)
            levels = floor_heights(heights, [f["z"] for f in layout["floors"]])
            layout["levels"] = levels
            for low, high, squares in staircases(heights, levels):
                roots[fdid].setdefault("stairs", []).append(pack_stair(place, low, high, squares))
                count += 1
        stats["staircases"] = count

    # 7. Output: models in first-seen order, rooms renumbered from 1 within each.
    order, placed = {}, defaultdict(list)
    bad_extents = tilted = 0
    for cont in sorted(by_cont):
        for place in sorted(by_cont[cont], key=lambda p: p["uid"]):
            fdid = place["file"]
            if fdid not in models or not place["flags"] & 0x8:
                continue
            if abs(place["rot"][0]) > 5 or abs(place["rot"][2]) > 5:
                # Leaning buildings (wrecks, fallen towers): their top-down
                # pictures don't fit the ground. A lean of a few degrees moves
                # a room by about a yard, and is drawn as if level.
                tilted += 1
                continue
            if not extents_match(place, roots[fdid]):
                bad_extents += 1
                continue
            index = order.setdefault(fdid, len(order) + 1)
            north, west = to_world(place, 0, 0)
            placed[cont].append((index, north, west, place["rot"][1] % 360, place["scale"]))
    if bad_extents:
        print(f"warning: {bad_extents} placements whose extents disagree with the transform; skipped")
    stats["tilted skipped"] = tilted
    out_models = []
    for fdid, index in sorted(order.items(), key=lambda item: item[1]):
        rooms = models[fdid]
        layout = roots[fdid]["layout"]
        numbering = {g: k + 1 for k, g in enumerate(sorted(rooms))}
        floors = "|".join(",".join(f["label"] for f in layout[p]["floors"]) for p in sorted(layout))
        out_rooms = []
        for g in sorted(rooms):
            room = rooms[g]
            out_rooms.append(dict(room, bits=pack_bits(room["columns"], room["rows"], room["cells"]),
                                  neighbours=[numbering[n] for n in room["near"]]))
        out_models.append(dict(floors=floors, rooms=out_rooms, stairs=roots[fdid].get("stairs"),
                               comment=f"{fdid} ({len(rooms)} rooms)"))
    stats["models"] = len(out_models)
    stats["buildings"] = sum(len(v) for v in placed.values())
    write_lua(args.output, build, out_models, placed, stats)


if __name__ == "__main__":
    main()
