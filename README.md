TooltipExtraData is a simple addon that adds extra data to tooltip.
Available from [Curseforge](https://www.curseforge.com/wow/addons/tooltipextradata)

## Features

*   shows current/max on right side of title
*   shows ItemID on item tooltips
*   shows SpellID on spell tooltips
*   shows IconID (texture FileID) below ItemID/SpellID
*   shows Player Ilvl

Supports Retail (Midnight) and WoW Forever

## Releasing

Releases are packaged and uploaded to CurseForge by the [BigWigs packager](https://github.com/BigWigsMods/packager) GitHub Action (`.github/workflows/release.yml`).

1.  Run `scripts/release.ps1 -Version X.Y.Z` to move `[Unreleased]` in `CHANGELOG.md` to the new version and update `## Version` in the TOC.
2.  Commit and push to `main`.
3.  Push a tag: `git tag vX.Y.Z` and `git push origin vX.Y.Z`.

The workflow reads the CurseForge project ID and game versions from the TOC (`## X-Curse-Project-ID`, `## Interface`), uses `CHANGELOG.md` as the release notes and excludes the files listed in `.pkgmeta`. Tags containing `alpha` or `beta` are uploaded with that release type.

Required repository secret: `CF_API_KEY` (CurseForge API token). Optional: `WOWI_API_TOKEN` for WoWInterface.