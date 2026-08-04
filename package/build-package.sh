#!/usr/bin/env bash
# Build and audit the public universal BYO-data package.
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  printf 'package error: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PORT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
REPO_ROOT=$(cd -- "$PORT_DIR/../.." && pwd -P)
STATIC_DIR="$SCRIPT_DIR/universal"
BINARY=${HGO_PACKAGE_BINARY:-"$PORT_DIR/hitmango-universal"}
OUTPUT=${1:-"$PORT_DIR/.build/hitmango.zip"}
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1785628800}

if [[ ${HGO_SKIP_BUILD:-0} != 1 ]]; then
  "$PORT_DIR/build_universal.sh"
fi
[[ -x "$BINARY" ]] || fail "universal loader is missing: $BINARY"

for tool in awk bash dirname file find grep install mkdir mktemp readelf rm \
            sed sha256sum sort touch unzip zip; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing host tool: $tool"
done

case "$SOURCE_DATE_EPOCH" in
  ''|*[!0-9]*) fail "SOURCE_DATE_EPOCH must be a Unix timestamp" ;;
esac
(( SOURCE_DATE_EPOCH >= 315532800 )) ||
  fail "SOURCE_DATE_EPOCH predates ZIP timestamps"
(( SOURCE_DATE_EPOCH <= 4354819198 )) ||
  fail "SOURCE_DATE_EPOCH exceeds ZIP timestamps"
(( SOURCE_DATE_EPOCH % 2 == 0 )) ||
  fail "SOURCE_DATE_EPOCH must use ZIP's two-second granularity"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hitmango-package.XXXXXX")
STAGE="$TMP_ROOT/stage"
TMP_ZIP="$TMP_ROOT/hitmango.zip"
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM
mkdir -p "$STAGE/hitmango/assets" "$STAGE/hitmango/lib"

put() {
  local mode=$1 source=$2 destination=$3
  [[ -f "$source" ]] || fail "missing package source: $source"
  install -D -m "$mode" -- "$source" "$STAGE/$destination"
}

put 0755 "$PORT_DIR/Hitman GO.sh" "Hitman GO.sh"
put 0755 "$BINARY" "hitmango/hitmango"
put 0755 "$PORT_DIR/run.sh" "hitmango/run.sh"
put 0644 "$PORT_DIR/README.md" "hitmango/README.md"
put 0644 "$PORT_DIR/NOTICE.md" "hitmango/NOTICE.md"
if [[ -f "$PORT_DIR/LICENSE" ]]; then
  put 0644 "$PORT_DIR/LICENSE" "hitmango/LICENSE"
else
  put 0644 "$REPO_ROOT/LICENSE" "hitmango/LICENSE"
fi
put 0644 "$STATIC_DIR/assets/README.txt" "hitmango/assets/README.txt"
put 0644 "$STATIC_DIR/lib/README.txt" "hitmango/lib/README.txt"
put 0644 "$PORT_DIR/version.txt" "hitmango/version.txt"
put 0755 "$PORT_DIR/nxextract.py" "hitmango/nxextract.py"
put 0755 "$PORT_DIR/nxextract-ui" "hitmango/nxextract-ui"
put 0755 "$PORT_DIR/nxextract-runtime-env.sh" "hitmango/nxextract-runtime-env.sh"
put 0755 "$PORT_DIR/run-extractor.sh" "hitmango/run-extractor.sh"
put 0644 "$PORT_DIR/extractor.json" "hitmango/extractor.json"
put 0644 "$PORT_DIR/nxextract-version.txt" "hitmango/nxextract-version.txt"
put 0644 "$PORT_DIR/gamedata/LEIA-ME.txt" "hitmango/gamedata/LEIA-ME.txt"
put 0644 "$PORT_DIR/INSTALLATION.md" "hitmango/INSTALLATION.md"

glibc_at_most() {
  local candidate=$1 maximum=$2 newest version major minor machine
  machine=$(readelf -h "$candidate" |
    sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
  [[ $machine == AArch64 ]] ||
    fail "${candidate#"$STAGE/"} is not AArch64 (found: $machine)"
  newest=$(readelf --version-info "$candidate" 2>/dev/null |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1)
  [[ -n $newest ]] ||
    fail "cannot determine glibc ABI: ${candidate#"$STAGE/"}"
  version=${newest#GLIBC_}
  major=${version%%.*}
  minor=${version#*.}; minor=${minor%%.*}
  if (( major > 2 || (major == 2 && minor > maximum) )); then
    fail "${candidate#"$STAGE/"} requires $newest (maximum: GLIBC_2.$maximum)"
  fi
}

# Audit every executable object in the staged release. The loader is the only
# ELF allowed; original Android libraries must be supplied by the owner later.
while IFS= read -r -d '' candidate; do
  kind=$(file -b "$candidate")
  case "$kind" in
    *ELF*)
      relative=${candidate#"$STAGE/"}
      case "$relative" in
        hitmango/hitmango|hitmango/nxextract-ui) ;;
        *) fail "unexpected ELF entered package: $relative" ;;
      esac
      glibc_at_most "$candidate" 30
      ;;
    *PE32*|*Mach-O*)
      fail "foreign executable entered package: ${candidate#"$STAGE/"}"
      ;;
  esac
done < <(find "$STAGE" -type f -print0)

TLS_FILESZ=$(readelf -lW "$STAGE/hitmango/hitmango" |
  awk '$1 == "TLS" { value=$5 } END { print value }')
PAD_LAYOUT=$(readelf -sW "$STAGE/hitmango/hitmango" |
  awk '$4 == "TLS" && $8 == "g_bionic_guard_pad" {
    value=$2 ":" $3
  } END { print value }')
[[ $TLS_FILESZ == 0x000100 && $PAD_LAYOUT == 0000000000000000:256 ]] ||
  fail "audited TLS layout changed: template=$TLS_FILESZ pad=$PAD_LAYOUT"

sh -n "$STAGE/Hitman GO.sh" "$STAGE/hitmango/run.sh"
if grep -En '^[[:space:]]*(export[[:space:]]+)?SDL_(VIDEO|AUDIO)DRIVER=' \
    "$STAGE/Hitman GO.sh" "$STAGE/hitmango/run.sh"; then
  fail "launcher must not force an SDL video or audio backend"
fi
if grep -En \
    '(^|[[:space:]])(setsid|nohup|systemctl[[:space:]]+(stop|mask))([[:space:]]|$)' \
    "$STAGE/Hitman GO.sh" "$STAGE/hitmango/run.sh"; then
  fail "launcher contains a forbidden lifecycle command"
fi

if find "$STAGE" \( \
    -iname '*.apk' -o -iname '*.apkm' -o -iname '*.apks' -o \
    -iname '*.xapk' -o -iname '*.obb' -o -iname '*.dex' -o \
    -name 'libmain.so' -o -name 'libunity.so' -o \
    -name 'libil2cpp.so' -o -name 'libFirebaseCppApp-*.so' -o \
    -name 'global-metadata.dat' -o -name 'sharedassets*' -o \
    -name '*.unity3d' \
  \) -print -quit | grep -q .; then
  fail "proprietary game data entered the public staging tree"
fi
if find "$STAGE" \( \
    -iname '*.log' -o -iname '*.raw' -o -iname '*.ppm' -o \
    -name 'HANDOFF.md' -o -name '__pycache__' -o -name '*.pyc' -o \
    -name 'home' -o -name 'userdata' \
  \) -print -quit | grep -q .; then
  fail "development or personal artifact entered the public staging tree"
fi
if grep -IRnE '192[.]168[.]|/home/|/mnt/ARQUIVOS|root@' "$STAGE" \
    --include='*.sh' --include='*.md' --include='*.txt'; then
  fail "release text contains a test address or personal path"
fi

(
  cd "$STAGE"
  find . -type f ! -path './hitmango/PACKAGE-MANIFEST.sha256' \
    -printf '%P\n' | sort | while IFS= read -r relative; do
      sha256sum -- "$relative"
    done
) > "$STAGE/hitmango/PACKAGE-MANIFEST.sha256"

find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
  cd "$STAGE"
  find . -type f -printf '%P\n' | sort | zip -X -9 -q "$TMP_ZIP" -@
)
unzip -tq "$TMP_ZIP" >/dev/null

VERIFY="$TMP_ROOT/verify"
mkdir -p "$VERIFY"
unzip -q "$TMP_ZIP" -d "$VERIFY"
(
  cd "$VERIFY"
  sha256sum -c hitmango/PACKAGE-MANIFEST.sha256 >/dev/null
)

mkdir -p "$(dirname -- "$OUTPUT")"
OUTPUT_DIR=$(cd -- "$(dirname -- "$OUTPUT")" && pwd -P)
OUTPUT="$OUTPUT_DIR/$(basename -- "$OUTPUT")"
install -m 0644 "$TMP_ZIP" "$OUTPUT"
(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename -- "$OUTPUT")" > "$(basename -- "$OUTPUT").sha256"
)

printf 'PACKAGE OK: %s\n' "$OUTPUT"
printf 'loader ABI: GLIBC <= 2.30 | TLS %s %s\n' \
  "$TLS_FILESZ" "$PAD_LAYOUT"
sha256sum "$BINARY" "$OUTPUT"
