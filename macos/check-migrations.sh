#!/bin/bash
# Called only after the launcher has validated and locked the selected disk.
set -euo pipefail
(( $# == 7 || $# == 8 )) || exit 64
qemu=$1 kernel=$2 initramfs=$3 command_line=$4 disk=$5 payload=$6 output=$7
unit=$(base64 < "$payload/migration-check.service" | tr -d '\r\n')
append="$command_line systemd.unit=try-omarchy-check.service systemd.set_credential_binary=systemd.extra-unit.try-omarchy-check.service:$unit systemd.mask=try-omarchy-migrate-alacritty.service"
(( ${#append} < 2048 )) || { echo 'Migration inspection boot arguments exceed the ARM64 limit' >&2; exit 1; }
lock_args=(-no-reboot)
if (( $# == 8 )); then
  [[ $8 == 'fd=9,set=77,opaque=omarchy-persistent-lock' ]] || exit 64
  lock_args+=(-add-fd "$8")
fi
qemu_pid=''
cleanup() {
  if [[ -n $qemu_pid ]]; then
    kill "$qemu_pid" 2>/dev/null || true
    for ((stop=0; stop<40; stop++)); do
      kill -0 "$qemu_pid" 2>/dev/null || break
      sleep 0.05
    done
    kill -KILL "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
"$qemu" -name 'Try Omarchy Migration Check' \
  -machine virt,accel=hvf,gic-version=3 -cpu host,pmu=off \
  "${lock_args[@]}" \
  -smp 2 -m 2G -nodefaults -display none -serial none -monitor none \
  -kernel "$kernel" -initrd "$initramfs" -append "$append" \
  -drive "if=none,id=root,file=${disk//,/,,},format=raw,snapshot=on" \
  -device virtio-blk-pci,drive=root \
  -fsdev "local,id=payload,path=${payload//,/,,},security_model=none,readonly=on" \
  -device virtio-9p-pci,fsdev=payload,mount_tag=try-omarchy-settings,romfile= \
  -device virtio-serial-pci,id=serial \
  -chardev "file,id=console,path=${output//,/,,}/console.log" \
  -device virtconsole,bus=serial.0,chardev=console \
  -chardev "file,id=report,path=${output//,/,,}/report.json" \
  -device virtserialport,bus=serial.0,chardev=report,name=dev.tryomarchy.settings \
  -chardev null,id=battery \
  -device virtserialport,bus=serial.0,chardev=battery,name=dev.tryomarchy.battery &
qemu_pid=$!
for ((attempt=0; attempt<1200; attempt++)); do
  state=$(ps -p "$qemu_pid" -o state= 2>/dev/null || true)
  if [[ -z $state || $state == *Z* ]]; then
    wait "$qemu_pid"
    qemu_pid=''
    [[ -s $output/report.json ]] || { echo 'Migration inspection returned no report' >&2; exit 1; }
    exit 0
  fi
  sleep 0.1
done
echo 'Migration inspection did not finish within two minutes' >&2
exit 1
