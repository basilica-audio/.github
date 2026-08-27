# 1. Suite vendor identity: brand in the display strings, personal identifiers frozen

* Status: accepted
* Deciders: Yves Vogl
* Date: 2026-08-27
* Scope: all thirteen plugins (Apotheosis, Aureate, Crypta, Firmament, Lancet, Miserere, Nave,
  Overture, Requiem, Seraph, Silentium, Tenebrae, Triptych)
* Supersedes nothing; referenced from each plugin's `docs/branding.md`

## Context and Problem Statement

Every customer-facing surface of the suite says **Basilica Audio** — the GitHub organisation, the
website, the icon set, all thirteen READMEs. Every *binary* said **Yves Vogl**, because
`juce_add_plugin`'s `COMPANY_NAME` was set to the author's personal name. That string is what a
host groups plugins by, so in Logic Pro's plugin manager, Cubase's vendor column and Reaper's FX
browser the suite filed under a person rather than under the brand the customer bought into.

Three separate identifiers carry the name, and they are not equally safe to change
(basilica-audio/.github#2):

| Identifier | What it drives | Cost of changing |
| --- | --- | --- |
| `COMPANY_NAME` | DAW vendor display, AU `name` string, VST3 vendor field | None. Display only. |
| `BUNDLE_ID` (`com.yvesvogl.*`) | macOS bundle identity, AU registration, codesign identifier, the preset JSON `plugin` field | High. A host treats a changed bundle ID as a different plugin. |
| `PresetManagerConfig::manufacturerName` | The user-preset folder on disk | High if changed alone: every preset the user already saved is orphaned. |

## Decision Drivers

* The brand must be what a host shows. That is the entire point of having one.
* No existing session may break. The suite is pre-1.0 but it is shipped and in use.
* No user may lose a preset, on either platform.
* The suite must never sit half-renamed — thirteen repos moving together or not at all.
* The copyright notice must stay legally accurate.

## Decision Outcome

**Display strings move to the brand; identifiers that a host or the filesystem keys on either stay
frozen or move with a migration.**

1. **`COMPANY_NAME "Basilica Audio"` — applied to all thirteen.**
   Verified to be display-only: the VST3 class ID derives from `PLUGIN_MANUFACTURER_CODE` +
   `PLUGIN_CODE` alone (JUCE 8.0.14, `juce_VST3ModuleInfo.h`, `VST3Interface::jucePluginId`), and
   the Audio Unit identity triple stays `(aufx, <PLUGIN_CODE>, Yvsv)`. Confirmed empirically by
   building Apotheosis before and after and diffing the AU `Info.plist` and the generated VST3
   identifiers — see `docs/branding.md` in any plugin repo for the recorded diff.

2. **`BUNDLE_ID` stays `com.yvesvogl.<plugin>` — deliberately, indefinitely.**
   Nothing user-visible flows from it. A change makes every existing project treat the plugin as a
   different one — the breakage Crypta already documented for its `twistyourguts` → `crypta`
   rename — with no benefit to weigh against it. The preset JSON `plugin` field is this same
   string, so freezing the bundle ID also keeps every preset file ever written importable. Each
   `CMakeLists.txt` carries a comment at the definition saying so, so that nobody later "finishes
   the rename".

3. **`manufacturerName` moves to `"Basilica Audio"`, with a copy-on-first-run migration.**
   `PresetManagerConfig` gains `legacyManufacturerName` (`"Yves Vogl"`). `PresetManager`'s
   constructor copies every `*.basilicapreset` file from the legacy folder into the new one, never
   overwriting a file that already exists there, and **never deletes or moves the originals** — an
   older build of the plugin, or a downgrade, still finds its presets exactly where it left them.
   The migration is idempotent and costs one `isDirectory()` check on a machine that never had the
   legacy folder.

4. **`COMPANY_COPYRIGHT "Copyright (c) 2026 Yves Vogl"` stays as it is.**
   Basilica Audio is a trading name; the copyright holder is the legal person. Aligning the two
   would make the notice less accurate, not more consistent.

### Consequences

* Good, because the suite now presents as one vendor in every host's browser, which is what the
  website, the READMEs and the product pages have always claimed.
* Good, because no session, no automation lane and no preset file changes meaning. The only moving
  parts are strings a human reads.
* Good, because the preset migration is copy-only and therefore reversible: downgrading to a build
  from before this change is survivable, which a move-based migration would not be.
* Bad, because the on-disk identifiers now disagree with the brand — `com.yvesvogl.apotheosis`
  inside a plugin called Basilica Audio Apotheosis. That inconsistency is invisible to users and is
  cheaper than the alternative; it is recorded here so it reads as a decision rather than a
  leftover.
* Bad, because two preset folders exist per plugin for as long as users keep old versions
  installed. The legacy folder is read once and then ignored; it is never cleaned up automatically,
  because deleting a user's files to tidy a folder name is not a trade this project makes.

## Considered Options

* **Display only** — `COMPANY_NAME` alone, leaving `~/Library/Audio/Presets/Yves Vogl/` in place.
  Rejected: zero-risk but leaves the brand half-applied in the one place a user actually browses
  their own files.
* **Display + preset folder with migration** (chosen).
* **Full identity move including `BUNDLE_ID`** — rejected. It breaks every existing session across
  thirteen plugins at once to fix a string no user ever sees.

## Verification

* Identity keys diffed before and after on a real build (AU `Info.plist`, VST3 identifiers).
* A test in every repo asserts that a preset written under the legacy manufacturer folder still
  loads after the change, that the migration never overwrites a newer file, and that the current
  and legacy folder shapes match the platform convention on both macOS and Windows — the
  platform-shape assertions run on both CI runners, not just the developer's machine.

## Links

* basilica-audio/.github#2 — the issue this decision answers, with the original safe/unsafe analysis
* `docs/branding.md` in each plugin repository — which name appears where, and why
* JUCE 8.0.14, `juce_add_plugin` (`COMPANY_NAME`, `BUNDLE_ID`, `PLUGIN_MANUFACTURER_CODE`,
  `PLUGIN_CODE`, `COMPANY_COPYRIGHT`)
