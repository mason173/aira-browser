#!/usr/bin/env python3
"""Generate Aira's Icons8 iOS 27 Glyph font from licensed SVG sources.

Run through FontForge's Python runtime:

  fontforge -lang=py -script scripts/generate-aira-icons8-font.py

The source manifest owns stable Aira codepoints. Existing codepoints never move;
future licensed SVGs are appended with a new unused BMP private-use codepoint.
"""

import json
import os
import shutil
import struct
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import fontforge


REPO_ROOT = Path(__file__).resolve().parents[1]
VENDOR_ROOT = (
    REPO_ROOT / "resources/icon-sources/aira/vendor/icons8/ios-27-glyph"
)
SOURCE_MANIFEST_PATH = VENDOR_ROOT / "source-manifest.json"
FONT_OUTPUT_PATH = VENDOR_ROOT / "AiraOperationalIcons.ttf"
SELECTION_OUTPUT_PATH = VENDOR_ROOT / "selection.json"
FAMILY_NAME = "AiraOperationalIcons"
FONT_NAME = "AiraOperationalIcons"
FULL_NAME = "Aira Operational Icons"
TTF_CHECKSUM_MAGIC = 0xB1B0AFBA
TTF_EPOCH_OFFSET = 2082844800
SOURCE_DATE_EPOCH = 1704067200
ICON_FONT_EM = 1024
ICON_FONT_ASCENT = 512
ICON_FONT_DESCENT = 512
ICON_FONT_MIN_X = 0
ICON_FONT_MAX_X = ICON_FONT_EM
ICON_FONT_MIN_Y = -ICON_FONT_DESCENT
ICON_FONT_MAX_Y = ICON_FONT_ASCENT
ICON_FONT_BOUNDS_TOLERANCE = 1.5


def table_checksum(data, offset, length):
    padded_length = (length + 3) & ~3
    padded = data[offset : offset + length] + bytes(padded_length - length)
    return sum(struct.unpack(f">{padded_length // 4}I", padded)) & 0xFFFFFFFF


def normalize_ttf_timestamps(font_path):
    data = bytearray(font_path.read_bytes())
    table_count = struct.unpack_from(">H", data, 4)[0]
    records = {}
    for index in range(table_count):
        record_offset = 12 + index * 16
        tag, _checksum, offset, length = struct.unpack_from(
            ">4sIII", data, record_offset
        )
        records[tag.decode("ascii")] = (record_offset, offset, length)

    if "head" not in records:
        raise RuntimeError("Generated TTF is missing its head table.")
    fixed_ttf_time = SOURCE_DATE_EPOCH + TTF_EPOCH_OFFSET
    _head_record, head_offset, _head_length = records["head"]
    struct.pack_into(">I", data, head_offset + 8, 0)
    struct.pack_into(">Q", data, head_offset + 20, fixed_ttf_time)
    struct.pack_into(">Q", data, head_offset + 28, fixed_ttf_time)

    if "FFTM" in records:
        _fftm_record, fftm_offset, fftm_length = records["FFTM"]
        if fftm_length >= 28:
            struct.pack_into(">Q", data, fftm_offset + 4, fixed_ttf_time)
            struct.pack_into(">Q", data, fftm_offset + 12, fixed_ttf_time)
            struct.pack_into(">Q", data, fftm_offset + 20, fixed_ttf_time)

    for tag in ("head", "FFTM"):
        if tag not in records:
            continue
        record_offset, table_offset, table_length = records[tag]
        checksum = table_checksum(data, table_offset, table_length)
        struct.pack_into(">I", data, record_offset + 4, checksum)

    padded_length = (len(data) + 3) & ~3
    padded_font = data + bytes(padded_length - len(data))
    whole_font_checksum = sum(
        struct.unpack(f">{padded_length // 4}I", padded_font)
    ) & 0xFFFFFFFF
    checksum_adjustment = (TTF_CHECKSUM_MAGIC - whole_font_checksum) & 0xFFFFFFFF
    struct.pack_into(">I", data, head_offset + 8, checksum_adjustment)
    font_path.write_bytes(data)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def validate_source_svg(source_path):
    root = ET.parse(source_path).getroot()
    if local_name(root.tag) != "svg":
        raise RuntimeError(f"Source is not an SVG document: {source_path}")
    if root.attrib.get("viewBox") != "0 0 30 30":
        raise RuntimeError(f"Source must use viewBox 0 0 30 30: {source_path}")
    outlines = []
    for element in root.iter():
        element_name = local_name(element.tag)
        if element_name == "path":
            if not element.attrib.get("d"):
                raise RuntimeError(f"Source contains an empty path: {source_path}")
            outlines.append(element)
        elif element_name == "polygon":
            if not element.attrib.get("points"):
                raise RuntimeError(f"Source contains an empty polygon: {source_path}")
            outlines.append(element)
    if not outlines:
        raise RuntimeError(f"Source must contain at least one path or polygon outline: {source_path}")


def validate_imported_glyph_bounds(glyph, source_path):
    """Ensure the source SVG maps into the icon font alignment box.

    FontForge maps an SVG viewBox against the current font ascent/descent. For
    text fonts an asymmetric ascent/descent is normal, but icon fonts need the
    viewBox to become a stable square alignment box so ArkUI Text line layout
    does not visually drift under font-scale or baseline changes.
    """
    min_x, min_y, max_x, max_y = glyph.boundingBox()
    if min_x < ICON_FONT_MIN_X - ICON_FONT_BOUNDS_TOLERANCE:
        raise RuntimeError(f"Glyph extends left of icon box: {source_path} bbox={glyph.boundingBox()}")
    if max_x > ICON_FONT_MAX_X + ICON_FONT_BOUNDS_TOLERANCE:
        raise RuntimeError(f"Glyph extends right of icon box: {source_path} bbox={glyph.boundingBox()}")
    if min_y < ICON_FONT_MIN_Y - ICON_FONT_BOUNDS_TOLERANCE:
        raise RuntimeError(f"Glyph extends below icon box: {source_path} bbox={glyph.boundingBox()}")
    if max_y > ICON_FONT_MAX_Y + ICON_FONT_BOUNDS_TOLERANCE:
        raise RuntimeError(f"Glyph extends above icon box: {source_path} bbox={glyph.boundingBox()}")


def load_glyph_entries():
    source_manifest = json.loads(SOURCE_MANIFEST_PATH.read_text(encoding="utf-8"))
    source_entries = source_manifest.get("glyphs")
    if not isinstance(source_entries, list) or not source_entries:
        raise RuntimeError("Icons8 source manifest must declare at least one glyph")
    seen_names = set()
    seen_code_points = set()
    entries = []
    for source in sorted(source_entries, key=lambda entry: entry["glyph"]):
        name = source.get("glyph")
        code_point = source.get("codePoint")
        if not isinstance(name, str) or not name:
            raise RuntimeError("Icons8 source manifest contains an invalid glyph name")
        if name in seen_names:
            raise RuntimeError(f"Duplicate Icons8 glyph name: {name}")
        if not isinstance(code_point, int) or code_point < 0 or code_point > 0xFFFF:
            raise RuntimeError(f"Icons8 glyph has an invalid BMP codepoint: {name}")
        if code_point in seen_code_points:
            raise RuntimeError(f"Duplicate Icons8 codepoint: {code_point}")
        seen_names.add(name)
        seen_code_points.add(code_point)
        source_path = VENDOR_ROOT / source["sourceFile"]
        if not source_path.is_file():
            raise RuntimeError(f"Missing licensed SVG source: {source_path}")
        validate_source_svg(source_path)
        entries.append(
            {
                "name": name,
                "code": code_point,
                "sourcePath": source_path,
            }
        )
    return entries


def build_font(entries):
    VENDOR_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aira-icons8-ios27-") as temp_name:
        temp_root = Path(temp_name)
        temporary_font_path = temp_root / FONT_OUTPUT_PATH.name
        font = fontforge.font()
        font.encoding = "UnicodeBmp"
        font.em = ICON_FONT_EM
        font.ascent = ICON_FONT_ASCENT
        font.descent = ICON_FONT_DESCENT
        font.familyname = FAMILY_NAME
        font.fontname = FONT_NAME
        font.fullname = FULL_NAME
        font.weight = "Regular"
        font.os2_weight = 400
        font.version = "1.0"
        font.copyright = "Icons8 iOS 27 Glyph; commercially licensed by the Aira project owner"
        font.comment = (
            "Aira Operational Icon subset generated from user-provided licensed SVG sources."
        )
        os.environ["SOURCE_DATE_EPOCH"] = str(SOURCE_DATE_EPOCH)

        for entry in entries:
            glyph = font.createChar(entry["code"], f"uni{entry['code']:04X}")
            glyph.importOutlines(str(entry["sourcePath"]))
            glyph.removeOverlap()
            glyph.correctDirection()
            glyph.round()
            glyph.width = ICON_FONT_EM
            validate_imported_glyph_bounds(glyph, entry["sourcePath"])

        font.generate(str(temporary_font_path))
        font.close()
        normalize_ttf_timestamps(temporary_font_path)
        shutil.copyfile(temporary_font_path, FONT_OUTPUT_PATH)

    selection = {
        "IcoMoonType": "selection",
        "icons": [
            {"properties": {"name": entry["name"], "code": entry["code"]}}
            for entry in entries
        ],
        "preferences": {
            "fontPref": {
                "metadata": {
                    "fontFamily": FAMILY_NAME,
                    "description": "Aira Operational Icon font",
                    "license": "Commercial license held by the project owner",
                }
            }
        },
    }
    SELECTION_OUTPUT_PATH.write_text(
        json.dumps(selection, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(
        f"Generated {FONT_OUTPUT_PATH.relative_to(REPO_ROOT)} and "
        f"{SELECTION_OUTPUT_PATH.relative_to(REPO_ROOT)} for {len(entries)} glyphs."
    )


def main():
    build_font(load_glyph_entries())


if __name__ == "__main__":
    main()
