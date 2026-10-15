#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
temporary=$(mktemp -d /private/tmp/try-migration-check-test.XXXXXX)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/payload" "$temporary/output"
cp "$root/macos/migration-check.service" "$temporary/payload/"
cat >"$temporary/qemu" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$CHECK_ARGUMENTS"
[[ ${CHECK_FAIL:-0} == 0 ]] || exit 19
for argument in "$@"; do
  case "$argument" in
    file,id=report,path=*) printf '{}\n' >"${argument#file,id=report,path=}" ;;
  esac
done
SH
chmod +x "$temporary/qemu"
export CHECK_ARGUMENTS="$temporary/arguments"
exec 9>"$temporary/workspace.lock"
"$root/macos/check-migrations.sh" "$temporary/qemu" kernel initramfs 'root=/dev/vda rw' \
  "$temporary/disk" "$temporary/payload" "$temporary/output" 'fd=9,set=77,opaque=omarchy-persistent-lock'
python3 - "$temporary/arguments" "$temporary/disk" <<'PY'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_text().splitlines()
def value(option):
    return args[args.index(option) + 1]
assert value('-display') == 'none'
assert value('-drive') == f'if=none,id=root,file={sys.argv[2]},format=raw,snapshot=on'
assert value('-add-fd') == 'fd=9,set=77,opaque=omarchy-persistent-lock'
assert '-netdev' not in args and '-nic' not in args
assert value('-fsdev').endswith('security_model=none,readonly=on')
assert 'systemd.unit=try-omarchy-check.service' in value('-append')
assert 'tryomarchy.fixes=' not in value('-append')
assert not any('clipboard' in a or 'authentication' in a or 'camera' in a for a in args)
PY
if CHECK_FAIL=1 "$root/macos/check-migrations.sh" "$temporary/qemu" kernel initramfs 'root=/dev/vda rw' \
  "$temporary/disk" "$temporary/payload" "$temporary/output"; then
  echo 'migration-inspection.test: a failed guest was accepted' >&2
  exit 1
else
  [[ $? == 19 ]]
fi
echo 'migration-inspection.test: disposable writes, isolated devices, lock retention, and guest failure: PASS'
