#!/usr/bin/env python3
"""blocked-by-exclusion.py — recipes that cannot build because an excluded
dependency is unavailable.

build-package.sh refuses to build a dependency listed in build-exclusions.txt:
it wants the deb fetched from the repository instead. So a recipe whose
dependency closure reaches such an exclusion fails every pass, after doing the
full dependency resolution first, and lands in the queue's FAIL list next to
genuinely broken packages. On 2026-09-04 that was 15 of 23 triaged failures.

An exclusion is only fatal when the *version the build wants* is not published:
Termux builds a dependency at its recipe's current version, so a published but
stale dependency is refused exactly like an absent one (jackett wanted
dotnet-runtime-9.0 9.0.19 while the pool held an older build). libglvnd, by
contrast, is excluded and published at its recipe version, so the 54 recipes
that depend on it resolve it from the repository and build fine.

Usage:
    blocked-by-exclusion.py <published.tsv>   # "name<TAB>version" per line

Prints "name<TAB>reason" for each blocked recipe. Exit 0 always: an unparseable
recipe must not take the queue down, it just is not reported as blocked.
"""
from __future__ import annotations

import re
import sys
from collections import deque
from pathlib import Path

DEPENDS_KEYS = ("TERMUX_PKG_DEPENDS", "TERMUX_PKG_BUILD_DEPENDS")


def recipe_version(build_sh: Path) -> str | None:
    """Version the queue would build, or None when it is computed at runtime."""
    text = build_sh.read_text(errors="replace")
    version = revision = None
    for line in text.splitlines():
        m = re.match(r'^TERMUX_PKG_VERSION=["\']?([^"\'$\s]+)["\']?\s*$', line)
        if m and version is None:
            version = m.group(1)
        m = re.match(r'^TERMUX_PKG_REVISION=["\']?(\d+)["\']?\s*$', line)
        if m and revision is None:
            revision = m.group(1)
    if not version:
        return None
    # An epoch is carried in TERMUX_PKG_VERSION itself, so nothing to add here.
    return f"{version}-{revision}" if revision else version


def load_graph(root: Path) -> tuple[dict[str, set[str]], dict[str, str]]:
    """Returns (recipe -> dependency recipes, deb name -> owning recipe)."""
    owner: dict[str, str] = {}
    for build_sh in root.glob("packages/*/build.sh"):
        owner[build_sh.parent.name] = build_sh.parent.name
    for sub in root.glob("packages/*/*.subpackage.sh"):
        # Dependencies name subpackages ("dotnet-runtime-9.0"), not the recipe
        # that produces them ("dotnet9.0"); without this the closure silently
        # matches nothing for exactly the packages that need it most.
        owner[sub.name[: -len(".subpackage.sh")]] = sub.parent.name

    deps: dict[str, set[str]] = {}
    for build_sh in root.glob("packages/*/build.sh"):
        text = build_sh.read_text(errors="replace")
        found: set[str] = set()
        for key in DEPENDS_KEYS:
            for m in re.finditer(rf'{key}\+?="([^"]*)"', text):
                for item in m.group(1).replace("\n", " ").split(","):
                    item = item.strip()
                    if not item:
                        continue
                    found.add(owner.get(item.split()[0], item.split()[0]))
        deps[build_sh.parent.name] = found
    return deps, owner


def fatal_exclusions(root: Path, owner: dict[str, str], published: dict[str, str]) -> dict[str, str]:
    """Excluded recipes whose wanted version is not in the repository."""
    excluded = set()
    for line in (root / "build-exclusions.txt").read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            excluded.add(line)
    fatal: dict[str, str] = {}
    for recipe in excluded:
        build_sh = root / "packages" / recipe / "build.sh"
        if not build_sh.is_file():
            continue
        want = recipe_version(build_sh)
        debs = [name for name, parent in owner.items() if parent == recipe]
        if want is None:
            # Version is computed at build time; treat any published deb as
            # good enough rather than blocking the whole subtree on a guess.
            if not any(name in published for name in debs):
                fatal[recipe] = "excluded and not published"
            continue
        if not any(name in published for name in debs):
            fatal[recipe] = "excluded and not published"
        elif not any(published.get(name) == want for name in debs):
            have = next((published[n] for n in debs if n in published), "?")
            fatal[recipe] = f"excluded, published {have} but recipe wants {want}"
    return fatal


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(".").resolve()
    published: dict[str, str] = {}
    for line in Path(argv[1]).read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2:
            published[parts[0]] = parts[1]

    deps, owner = load_graph(root)
    fatal = fatal_exclusions(root, owner, published)
    if not fatal:
        return 0

    for recipe in sorted(deps):
        # Walk the closure, stopping at anything already published: the build
        # downloads those instead of recursing into their own dependencies.
        seen: set[str] = set()
        queue = deque([recipe])
        hit: tuple[str, str] | None = None
        while queue and hit is None:
            current = queue.popleft()
            for dep in deps.get(current, ()):
                if dep in seen:
                    continue
                seen.add(dep)
                if dep in fatal:
                    hit = (dep, fatal[dep])
                    break
                if dep in published:
                    continue
                queue.append(dep)
        if hit is not None:
            print(f"{recipe}\t{hit[0]} ({hit[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
