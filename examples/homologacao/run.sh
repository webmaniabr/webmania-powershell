#!/bin/sh
# Exemplo neutro de homologação: roda examples/homologacao/run.ps1 com o módulo deste checkout.
# Sem WEBMANIA_LIVE=1 o exemplo não importa o módulo nem faz requisições (saída 77).
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${WEBMANIA_LIVE:-}" != "1" ]; then printf '%s\n' '{"result":"blocked"}'; exit 77; fi
exec pwsh -NoLogo -NoProfile -NonInteractive -File "$here/run.ps1"
