#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_DIR/artifacts/local}"
mkdir -p "$OUT_DIR/receipts"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
IMAGE='mcr.microsoft.com/dotnet/sdk@sha256:afd0ccff9d306812a69ef0f47458376b6acb544ae866cfc4b8d28ff0eef35ea7'
printf 'nameserver 127.0.0.1\noptions timeout:1 attempts:2\n' > "$OUT_DIR/resolv.conf"
run() {
  name="$1"; shift
  extra=()
  if [[ "$name" == delta ]]; then extra+=(--mount "type=bind,source=$OUT_DIR/resolv.conf,target=/etc/resolv.conf"); fi
  if [[ "$name" == locale-c ]]; then extra+=(-e LANG=C -e LC_ALL=C); fi
  if [[ "$name" == locale-utf8 ]]; then extra+=(-e LANG=C.UTF-8 -e LC_ALL=C.UTF-8); fi
  container="webmania-ps-$name-$(date -u +%s)"
  args=(run "${extra[@]}" --name "$container" --rm --pull=never --platform linux/arm64 --network none --cpus 1 --memory 1536m --pids-limit 256 --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,nodev,size=384m -e HOME=/tmp -e DOTNET_CLI_TELEMETRY_OPTOUT=1 --mount "type=bind,source=$REPO_DIR,target=/repo,readonly" --mount "type=bind,source=$OUT_DIR,target=/out" "$IMAGE" pwsh -NoLogo -NoProfile -NonInteractive "$@")
  printf '%q ' docker "${args[@]}" > "$OUT_DIR/receipts/$name.command.txt"
  printf '\n' >> "$OUT_DIR/receipts/$name.command.txt"
  set +e
  docker "${args[@]}" > "$OUT_DIR/$name.log" 2>&1
  status=$?
  set -e
  printf '{"case":"%s","exitCode":%s,"container":"%s","cpus":1,"memoryBytes":1610612736,"pids":256,"tmpfsBytes":402653184,"network":"none","rm":true,"image":"%s"}\n' "$name" "$status" "$container" "$IMAGE" > "$OUT_DIR/receipts/$name.json"
  cat "$OUT_DIR/$name.log"
  return "$status"
}
run runtime-build -File /repo/scripts/Build-Runtime.ps1 -OutputDirectory /out/runtime-build
cmp "$REPO_DIR/module/Webmania/bin/Webmania.PowerShell.Runtime.dll" "$OUT_DIR/runtime-build/Webmania.PowerShell.Runtime.dll"
run generate -File /repo/scripts/Generate.ps1 -OutputDirectory /out/generated
for path in Operations.ps1 Factories.ps1 commands.json; do cmp "$REPO_DIR/module/Webmania/$path" "$OUT_DIR/generated/$path"; done
run package -File /repo/scripts/Package.ps1 -OutputDirectory /out
ARCHIVE='/out/Webmania.0.1.0-alpha7.zip'
run lint -File /repo/tests/Lint.ps1 -OutputDirectory /out
run provenance -File /repo/tests/Provenance.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run test -File /repo/tests/Test.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
for guard in dependency bridge sdk-conflict bridge-conflict wildcard-root; do run "import-$guard" -File /repo/tests/Import-Probe.ps1 -Case "$guard" -Archive "$ARCHIVE" -OutputDirectory /out; done
run lifecycle -File /repo/tests/Lifecycle.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run scalar-privacy -File /repo/tests/ScalarPrivacy.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run pipeline-privacy -File /repo/tests/PipelinePrivacy.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run locale-c -File /repo/tests/Locale.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run locale-utf8 -File /repo/tests/Locale.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
# Invalid UTF-16 in free selectors is rejected before dispatch without losing native cancellation.
run unicode -File /repo/tests/Unicode.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
run delta -File /repo/tests/Delta.ps1 -Archive "$ARCHIVE" -OutputDirectory /out
