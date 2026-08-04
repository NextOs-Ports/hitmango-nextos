#!/usr/bin/env bash
# Build and audit the private, full-data NextOS Elite R2 release.
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  printf 'R2 package error: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PORT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
REPO_ROOT=$(cd -- "$PORT_DIR/../.." && pwd -P)
DATA_ROOT=${HGO_R2_DATA_ROOT:-${1:-}}
ICON=${HGO_R2_ICON:-${2:-}}
OUTPUT_DIR=${HGO_R2_OUTPUT_DIR:-${3:-"$PORT_DIR/.build/r2"}}
RELEASE_NAME='Hitman GO (NextOS Elite)'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1785628800}

[[ -n "$DATA_ROOT" && -d "$DATA_ROOT/assets" ]] ||
  fail "pass the extracted APK root containing assets/ as argument 1"
[[ -n "$ICON" && -f "$ICON" ]] ||
  fail "pass the final PNG icon as argument 2"

for tool in awk bash cmp cp dirname file find grep gzip identify install mkdir \
            mktemp python3 readelf rm sed sha256sum sort tar touch unzip zip; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing host tool: $tool"
done

NEXTOS_BASE=${NEXTOS_ROOT:-"${HOME}/NextOS-Elite-Edition"}
TOOLCHAIN=${NEXTOS_TOOLCHAIN:-$(
  find -H "$NEXTOS_BASE" -maxdepth 2 -type d \
    -path '*/build.NextOS-Retro-Elite-Edition-Amlogic-old.aarch64-*/toolchain' \
    -print | sort -V | tail -1
)}
[[ -n "$TOOLCHAIN" && -d "$TOOLCHAIN" ]] ||
  fail "current NextOS AArch64 toolchain was not found"
READELF="$TOOLCHAIN/bin/aarch64-libreelec-linux-gnu-readelf"
STRIP="$TOOLCHAIN/bin/aarch64-libreelec-linux-gnu-strip"
SYSROOT_LIBC="$TOOLCHAIN/aarch64-libreelec-linux-gnu/sysroot/usr/lib/libc.so.6"
[[ -x "$READELF" && -x "$STRIP" && -f "$SYSROOT_LIBC" ]] ||
  fail "current NextOS toolchain/sysroot is incomplete"

if [[ ${HGO_R2_SKIP_BUILD:-0} != 1 ]]; then
  NEXTOS_ROOT="$NEXTOS_BASE" NEXTOS_TOOLCHAIN="$TOOLCHAIN" \
    "$PORT_DIR/build.sh"
fi
BINARY=${HGO_R2_BINARY:-"$PORT_DIR/hitmango"}
[[ -x "$BINARY" ]] || fail "NextOS loader is missing: $BINARY"

SYSROOT_GLIBC=$(
  "$READELF" -V "$SYSROOT_LIBC" |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1
)
LOADER_GLIBC=$(
  "$READELF" -V "$BINARY" |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1
)
[[ -n "$SYSROOT_GLIBC" && -n "$LOADER_GLIBC" ]] ||
  fail "could not audit sysroot/loader glibc versions"
highest=$(printf '%s\n%s\n' "$SYSROOT_GLIBC" "$LOADER_GLIBC" | sort -V | tail -1)
[[ $highest == "$SYSROOT_GLIBC" ]] ||
  fail "loader requires $LOADER_GLIBC but current sysroot exposes $SYSROOT_GLIBC"

TLS_FILESZ=$(
  "$READELF" -lW "$BINARY" |
    awk '$1 == "TLS" { value=$5 } END { print value }'
)
PAD_LAYOUT=$(
  "$READELF" -sW "$BINARY" |
    awk '$4 == "TLS" && $8 == "g_bionic_guard_pad" {
      value=$2 ":" $3
    } END { print value }'
)
[[ $TLS_FILESZ == 0x000100 && $PAD_LAYOUT == 0000000000000000:256 ]] ||
  fail "source loader TLS layout changed: template=$TLS_FILESZ pad=$PAD_LAYOUT"

declare -a OWNER_LIBS=(
  libmain.so
  libunity.so
  libil2cpp.so
  libFirebaseCppApp-12_10_1.so
)
for library in "${OWNER_LIBS[@]}"; do
  [[ -s "$DATA_ROOT/lib/arm64-v8a/$library" ]] ||
    fail "owner library is missing: lib/arm64-v8a/$library"
done
for required in \
  assets/bin/Data/boot.config \
  assets/bin/Data/globalgamemanagers \
  assets/bin/Data/Managed/Metadata/global-metadata.dat; do
  [[ -s "$DATA_ROOT/$required" ]] || fail "owner data is missing: $required"
done

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hitmango-r2.XXXXXX")
STAGE="$TMP_ROOT/stage"
VERIFY_TAR="$TMP_ROOT/verify-tar"
VERIFY_ZIP="$TMP_ROOT/verify-zip"
TMP_TAR="$TMP_ROOT/$RELEASE_NAME.tar.gz"
TMP_ZIP="$TMP_ROOT/$RELEASE_NAME.zip"
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM
mkdir -p "$STAGE/ports/hitmango/assets" "$STAGE/ports/hitmango/lib" \
  "$STAGE/ports/hitmango/home" "$STAGE/ports_scripts/images"

install -m 0755 "$BINARY" "$STAGE/ports/hitmango/hitmango"
"$STRIP" --strip-unneeded "$STAGE/ports/hitmango/hitmango"
install -m 0755 "$PORT_DIR/run.sh" "$STAGE/ports/hitmango/run.sh"
install -m 0755 "$SCRIPT_DIR/r2/Hitman GO.sh" \
  "$STAGE/ports_scripts/Hitman GO.sh"
install -m 0644 "$PORT_DIR/README.md" "$STAGE/ports/hitmango/README.md"
install -m 0644 "$PORT_DIR/NOTICE.md" "$STAGE/ports/hitmango/NOTICE.md"
install -m 0644 "$REPO_ROOT/LICENSE" "$STAGE/ports/hitmango/LICENSE"
install -m 0644 "$ICON" "$STAGE/ports_scripts/images/Hitman GO.png"

cp -a --reflink=auto "$DATA_ROOT/assets/." "$STAGE/ports/hitmango/assets/"
for library in "${OWNER_LIBS[@]}"; do
  install -m 0644 "$DATA_ROOT/lib/arm64-v8a/$library" \
    "$STAGE/ports/hitmango/lib/$library"
done

find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE/ports/hitmango/hitmango" \
  "$STAGE/ports/hitmango/run.sh" "$STAGE/ports_scripts/Hitman GO.sh"

LOADER_SHA=$(sha256sum "$STAGE/ports/hitmango/hitmango" | awk '{print $1}')
printf '%s\n' \
  'Target: NextOS Elite AArch64 / Amlogic-old' \
  'Build recipe: build.sh with the current official NextOS toolchain/sysroot' \
  "Sysroot libc symbol ceiling: $SYSROOT_GLIBC" \
  "Loader maximum required glibc symbol: $LOADER_GLIBC" \
  "Loader SHA-256: $LOADER_SHA" \
  > "$STAGE/ports/hitmango/BUILD-PROVENANCE.txt"
chmod 0644 "$STAGE/ports/hitmango/BUILD-PROVENANCE.txt"

sh -n "$STAGE/ports/hitmango/run.sh" "$STAGE/ports_scripts/Hitman GO.sh"
if grep -En \
    '(^|[[:space:]])(setsid|nohup|systemctl[[:space:]]+(stop|mask)|watchdog)([[:space:]]|$)' \
    "$STAGE/ports/hitmango/run.sh" "$STAGE/ports_scripts/Hitman GO.sh"; then
  fail "final launcher contains a forbidden lifecycle command"
fi
if grep -En '(^|[[:space:]])[^#]*&[[:space:]]*$' \
    "$STAGE/ports/hitmango/run.sh" "$STAGE/ports_scripts/Hitman GO.sh"; then
  fail "final launcher sends the game to background"
fi
if grep -En '^[[:space:]]*(export[[:space:]]+)?SDL_(VIDEO|AUDIO)DRIVER=' \
    "$STAGE/ports/hitmango/run.sh" "$STAGE/ports_scripts/Hitman GO.sh"; then
  fail "final launcher forces an SDL video/audio backend"
fi

mapfile -t EXECUTABLES < <(find "$STAGE" -type f -perm /111 -printf '%P\n' | sort)
EXPECTED_EXECUTABLES=$'ports/hitmango/hitmango\nports/hitmango/run.sh\nports_scripts/Hitman GO.sh'
[[ $(printf '%s\n' "${EXECUTABLES[@]}") == "$EXPECTED_EXECUTABLES" ]] || {
  printf 'unexpected executable allowlist:\n%s\n' "${EXECUTABLES[*]}" >&2
  fail "staging executable permissions are not allowlisted"
}

machine=$(
  "$READELF" -h "$STAGE/ports/hitmango/hitmango" |
    sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p'
)
[[ $machine == AArch64 ]] || fail "loader is not AArch64: $machine"
for library in "${OWNER_LIBS[@]}"; do
  machine=$(
    "$READELF" -h "$STAGE/ports/hitmango/lib/$library" |
      sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p'
  )
  [[ $machine == AArch64 ]] || fail "$library is not AArch64: $machine"
done

while IFS= read -r -d '' candidate; do
  kind=$(file -b "$candidate")
  case "$kind" in
    *ELF*)
      relative=${candidate#"$STAGE/"}
      case "$relative" in
        ports/hitmango/hitmango|ports/hitmango/lib/libmain.so|\
        ports/hitmango/lib/libunity.so|ports/hitmango/lib/libil2cpp.so|\
        ports/hitmango/lib/libFirebaseCppApp-12_10_1.so) ;;
        *) fail "unexpected ELF entered staging: $relative" ;;
      esac
      ;;
    *PE32*|*Mach-O*)
      fail "foreign executable entered staging: ${candidate#"$STAGE/"}"
      ;;
  esac
done < <(find "$STAGE" -type f -print0)

if find "$STAGE" \( \
    -iname '*.apk' -o -iname '*.apkm' -o -iname '*.apks' -o \
    -iname '*.xapk' -o -iname '*.obb' -o -iname '*.raw' -o \
    -iname '*.ppm' -o -iname '*.bak' -o -iname '*.core' -o \
    -name 'core.*' -o -name 'HANDOFF.md' -o -name '__pycache__' -o \
    -name '*.pyc' -o -name 'src' -o -name 'build.sh' \
  \) -print -quit | grep -q .; then
  fail "development, redundant package or diagnostic artifact entered staging"
fi
if find "$STAGE/ports/hitmango/home" -mindepth 1 -print -quit | grep -q .; then
  fail "personal save data entered staging"
fi
if grep -IRnE '192[.]168[.]|/home/|/mnt/ARQUIVOS|root@|r2_secret|access_key' \
    "$STAGE/ports/hitmango/README.md" \
    "$STAGE/ports/hitmango/NOTICE.md" \
    "$STAGE/ports/hitmango/BUILD-PROVENANCE.txt" \
    "$STAGE/ports/hitmango/run.sh" \
    "$STAGE/ports_scripts/Hitman GO.sh"; then
  fail "release text contains a test address, personal path or credential"
fi
identify "$STAGE/ports_scripts/images/Hitman GO.png" | grep -q ' PNG ' ||
  fail "frontend image is not PNG"

(
  cd "$STAGE"
  find . -type f ! -path './ports/hitmango/PACKAGE-MANIFEST.sha256' \
    -printf '%P\n' | sort | while IFS= read -r relative; do
      sha256sum -- "$relative"
    done
) > "$STAGE/ports/hitmango/PACKAGE-MANIFEST.sha256"
chmod 0644 "$STAGE/ports/hitmango/PACKAGE-MANIFEST.sha256"

find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 \
  --numeric-owner -C "$STAGE" -cf - ports ports_scripts |
  gzip -n -6 > "$TMP_TAR"
(
  cd "$STAGE"
  zip -X -9 -q -r "$TMP_ZIP" ports ports_scripts
)
gzip -t "$TMP_TAR"
unzip -tq "$TMP_ZIP" >/dev/null

mkdir -p "$VERIFY_TAR" "$VERIFY_ZIP"
tar -xzf "$TMP_TAR" -C "$VERIFY_TAR"
unzip -q "$TMP_ZIP" -d "$VERIFY_ZIP"
for verify in "$VERIFY_TAR" "$VERIFY_ZIP"; do
  (
    cd "$verify"
    sha256sum -c ports/hitmango/PACKAGE-MANIFEST.sha256 >/dev/null
  )
done

python3 - "$TMP_TAR" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    members = archive.getmembers()
    if not members:
        raise SystemExit("empty tar archive")
    for member in members:
        if member.uid != 0 or member.gid != 0:
            raise SystemExit(f"non-root archive owner: {member.name}")
        if member.name.startswith("/") or ".." in member.name.split("/"):
            raise SystemExit(f"unsafe archive path: {member.name}")
PY

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P)
FINAL_TAR="$OUTPUT_DIR/$RELEASE_NAME.tar.gz"
FINAL_ZIP="$OUTPUT_DIR/$RELEASE_NAME.zip"
install -m 0644 "$TMP_TAR" "$FINAL_TAR"
install -m 0644 "$TMP_ZIP" "$FINAL_ZIP"
sha256sum "$FINAL_TAR" > "$FINAL_TAR.sha256"
sha256sum "$FINAL_ZIP" > "$FINAL_ZIP.sha256"

FILE_COUNT=$(find "$STAGE" -type f | wc -l)
ASSET_COUNT=$(find "$STAGE/ports/hitmango/assets" -type f | wc -l)
printf 'R2 PACKAGE OK: %s\n' "$FINAL_TAR"
printf 'LOCAL ZIP OK: %s\n' "$FINAL_ZIP"
printf 'provenance: current NextOS sysroot %s | loader %s\n' \
  "$SYSROOT_GLIBC" "$LOADER_GLIBC"
printf 'loader: %s\n' "$LOADER_SHA"
printf 'files: %s total | %s owner assets\n' "$FILE_COUNT" "$ASSET_COUNT"
sha256sum "$FINAL_TAR" "$FINAL_ZIP"
