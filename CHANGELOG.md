# Changelog

## v1.1.1 — 2026-08-04

Field-report fixes (muOS/RG40XX-H and friends), same day as v1.1.0.

- **Pad outside SDL's built-in mapping database no longer loses ALL
  navigation** (muOS/RG40XX-H report: "the character won't move"): the loader
  now opens the pad as a raw joystick with positional button/axis order when
  no GameController mapping exists, and `run.sh` also feeds the CFW's
  `gamecontrollerdb.txt` to SDL when present.
- **NXExtract: a staged payload that fails whole-set validation is discarded**
  instead of being resumed and re-failing forever (local patch on top of
  1.2.1, recorded in `nxextract-version.txt`; candidate for upstream 1.2.2).
- **Recipe tolerances widened**: bigger XAPK/bundle member caps (3 GiB/6 GiB)
  and looser file-count floor so legitimate Play builds with slightly
  different packaging are not rejected as "different build".

## v1.1.0 — 2026-08-04

Compatibility review before the public release; parity with the fixes promoted
from the corrective releases of the other NextOS ports.

- **NXExtract 1.2.1 integrated (BYO-data installer)**: drop your legal Hitman
  GO 1.18.1 APK in `gamedata/` and the first launch validates, extracts and
  commits the data transactionally, with progress UI, resume and adoption of
  existing installs; your APK is never deleted. Fast marker validation on
  later launches (milliseconds, no SD rescan).
- **SELECT/START on pads without physical BTN_SELECT/BTN_START**
  (GO-Super/RK3326 family): the exit combo now also reads
  `BTN_TRIGGER_HAPPY1/2` via EV_KEY bitmap ordinals — additive probe, pads
  with real SELECT/START are untouched.
- **Unity RGBA8888 EGLConfig contract on Panfrost/Mesa** (RG-DS/ROCKNIX
  family): alpha 8 is requested first and the obtained config is logged once;
  Mesa returning RGBX8888 on the first match no longer risks a black screen
  (fix inherited from Horizon Chase v1.0.3).
- **SIGTERM/SIGINT converge on the SELECT+START shutdown**: pause, save and
  clean exit instead of a raw kill when the frontend or a supervisor sends
  TERM.
- Bilingual README with real photos, INSTALLATION.md, vendored-NXExtract
  version pins (`nxextract-version.txt`) and NXExtract license added.

## v1.0.0 — 2026-08-04

- Initial universal AArch64 release: Unity 2022.3.67f2 IL2CPP so-loader
  following the original Android lifecycle (constructors, `JNI_OnLoad`,
  `initJni`, surface, focus, resume, render, pause).
- All shipped ELFs require `GLIBC <= 2.30` (loader max: `GLIBC_2.27`);
  reproducible package build.
- Validated on NextOS Elite (Mali-450, fbdev/GLES2) and R36T-class
  ArkOS clone (Mali-G31, SDL/KMSDRM).
