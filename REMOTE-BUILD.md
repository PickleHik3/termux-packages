# Remote build (build-machine side)

This checkout builds VAJ `.deb` packages on any machine and hands them to the
central publish pipeline. **Full pipeline docs** (CI, signing, R2, secrets) live
in the APT repo: `PickleHik3/io-vaj-apt` → `REMOTE-BUILD.md`. This file covers
only the build machine.

## This machine needs only

- docker with the frozen image loaded: `io-vaj-phase0a-builder:c9cc6b28`
- this checkout on branch `io-vaj-package`
- `gh auth login` (a GitHub PAT, repo scope)

**No GPG key. No R2 credentials.** Debs are handed off as GitHub release assets;
all signing/publishing happens in GitHub Actions on `io-vaj-apt`.

## Load the frozen image (once)

Transfer `vaj-builder.tar.zst` from the primary host, then:

```bash
zstd -dc vaj-builder.tar.zst | docker load
```

(Primary host produces it with:
`docker save io-vaj-phase0a-builder:c9cc6b28 | zstd -T0 -19 > vaj-builder.tar.zst`)

## Build + hand off

```bash
./remote-build.sh                       # full queue (build-all-queue.sh, ~1,660 pkgs)
./remote-build.sh build-tier1-libs.txt  # one tier file
./remote-build.sh --pkgs zsh jq bc      # named packages
./remote-build.sh --pkgs zsh --no-publish   # build only, skip staging release
```

On success `remote-build.sh` runs `gh release create staging-<ts> --prerelease`
on `PickleHik3/io-vaj-apt` with the built debs. That prerelease triggers
`publish.yml`, which stages, signs, publishes to R2, then deletes the staging
release.

## Notes

- Container name is `vaj-remote-builder` — distinct from the primary host's
  `termux-package-builder`, so the two never collide.
- aarch64 only. The image cross-compiles regardless of host CPU (x86_64 host is fine).
- The script fails fast if the frozen image is missing or `gh` is unauthenticated.
- Start with a 1–2 package test wave before running the full queue.
