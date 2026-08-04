#!/bin/sh
# NextOS/PortMaster entry point. The runtime itself owns lifecycle and cleanup.
#
# Resolve o proprio caminho REAL antes de procurar: em alguns frontends o
# arquivo visivel e' um symlink ou copia (muOS faz isso), e `dirname $0`
# apontaria para o lugar errado. A busca relativa ao script vem primeiro e
# sempre vale; a lista fixa cobre os layouts de ROM conhecidos por CFW.
# Padrao herdado do fix Stardew Valley v1.1.6 (relato muOS/RG 40XX-H).

SELF=$0
[ -L "$SELF" ] && SELF=$(readlink -f -- "$SELF" 2>/dev/null || printf '%s' "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" 2>/dev/null && pwd -P) ||
  exit 1

for launcher in \
  "$SCRIPT_DIR/hitmango/run.sh" \
  "$SCRIPT_DIR/../ports/hitmango/run.sh" \
  "$SCRIPT_DIR/../../ports/hitmango/run.sh" \
  /roms/ports/hitmango/run.sh \
  /roms2/ports/hitmango/run.sh \
  /storage/roms/ports/hitmango/run.sh \
  /mnt/mmc/ports/hitmango/run.sh \
  /mnt/mmc/roms/ports/hitmango/run.sh \
  /mnt/mmc/ROMS/ports/hitmango/run.sh \
  /mnt/sdcard/ports/hitmango/run.sh \
  /mnt/sdcard/roms/ports/hitmango/run.sh \
  /mnt/sdcard/ROMS/ports/hitmango/run.sh \
  /userdata/roms/ports/hitmango/run.sh
do
  if [ -f "$launcher" ] && [ ! -L "$launcher" ]; then
    exec bash "$launcher" "$@"
  fi
done

# Falhar em silencio e' o pior modo de falha: o frontend descarta stderr, o
# port volta ao menu e NENHUM arquivo e' gerado. O erro fica gravado em disco.
message="Hitman GO: hitmango/run.sh not found (script=$SELF dir=$SCRIPT_DIR)"
printf '%s\n' "$message" >&2
for spot in "$SCRIPT_DIR/hitmango-launcher-error.log" \
            "${TMPDIR:-/tmp}/hitmango-launcher-error.log"
do
  if printf '%s\n' "$message" > "$spot" 2>/dev/null; then
    printf 'Hitman GO: detalhes em %s\n' "$spot" >&2
    break
  fi
done
exit 1
