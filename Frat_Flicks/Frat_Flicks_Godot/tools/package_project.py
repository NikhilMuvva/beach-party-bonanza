#!/usr/bin/env python3
"""Build a source ZIP that Godot's Project Manager can extract directly.

Godot 4.5 creates subdirectories from explicit ZIP directory entries, rather
than recursively creating the parent of each file. Emit every directory in
parent-first order before the files. Generated import caches are regenerated
by the receiving editor, so they are excluded from the source distribution.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".godot", ".git", "__pycache__", "logs", "builds"}


def source_files():
    files = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED_DIRS or part.startswith(".venv") for part in relative.parts):
            continue
        if path.suffix in {".import", ".pyc", ".zip"} or path.name == ".DS_Store":
            continue
        files.append(path)
    return sorted(files)


def package(destination: Path):
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    files = source_files()
    directories = {ROOT}
    for path in files:
        parent = path.parent
        while parent.is_relative_to(ROOT):
            directories.add(parent)
            if parent == ROOT:
                break
            parent = parent.parent
    with ZipFile(destination, "w", ZIP_DEFLATED, compresslevel=9) as archive:
        for directory in sorted(directories, key=lambda p: (len(p.relative_to(ROOT).parts), p.as_posix())):
            name = Path(ROOT.name) / directory.relative_to(ROOT)
            archive.write(directory, name.as_posix() + "/")
        for path in files:
            archive.write(path, (Path(ROOT.name) / path.relative_to(ROOT)).as_posix())
    with ZipFile(destination) as archive:
        assert archive.testzip() is None, "Corrupt ZIP member"
        created = set()
        for item in archive.infolist():
            name = Path(item.filename)
            if item.is_dir():
                assert name.parent == Path(".") or name.parent in created, "Directory out of order"
                created.add(name)
            else:
                assert name.parent in created, "Missing directory entry"
    print(f"Packaged {len(files)} files and {len(directories)} explicit folders: {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    package(parser.parse_args().output)
