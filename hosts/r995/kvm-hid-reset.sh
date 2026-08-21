# EIZO EV3895 内蔵KVMのHID用ハブ (VIA Labs 2109:2817, 2ポート) は切替時に
# ハングすることがあり、配下のキーボード・マウスが列挙されなくなる。
# このコマンドは再起動せずSSHから復旧を試みる:
#   1) ハブの unbind/rebind（軽度のハング向け）
#   2) xhci コントローラのリセット（再起動時の再初期化と同等。2026-08-22 の
#      事象はホスト再起動のみで復旧しており、これで直る変種が存在する）
# どちらも効かない場合はKVM内部ハブのハードハングなので、モニタの電源
# リセットが必要（手順を案内して終了する）。

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

# KVMのHID用ハブを探す。バス番号はブートごとに変わるため（過去に 7-1.2、
# 現在 5-1.2 を観測）、vendor:product とポート数(2)で特定する。
# 同じ 2109:2817 でも上流側ハブは4ポートなので maxchild で区別できる。
find_hub() {
  local d
  for d in /sys/bus/usb/devices/*; do
    [ -e "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor")" = "2109" ] || continue
    [ "$(cat "$d/idProduct")" = "2817" ] || continue
    [ "$(cat "$d/maxchild")" = "2" ] || continue
    basename "$d"
    return 0
  done
  return 1
}

# ハブ配下に列挙されたデバイス数。キーボード + マウスレシーバーで2になる。
hid_count() {
  local n=0 d
  for d in /sys/bus/usb/devices/"$1".*; do
    case $(basename "$d") in *:*) continue ;; esac # インターフェースは除外
    if [ -e "$d/idVendor" ]; then
      n=$((n + 1))
    fi
  done
  echo "$n"
}

recovered() {
  echo "復旧しました: ハブ $1 配下に $(hid_count "$1") 台のHIDデバイスを確認。"
}

hub=$(find_hub) || {
  echo "KVMのHID用ハブ (2109:2817, 2ポート) が見つかりません。" >&2
  echo "ハブ自体が列挙されていないため、モニタ (EV3895) の電源リセットが必要です。" >&2
  exit 1
}

if [ "$(hid_count "$hub")" -ge 2 ]; then
  echo "HIDデバイスは列挙済みです（ハブ $hub 配下に $(hid_count "$hub") 台）。対処は不要です。"
  exit 0
fi

echo "ハブ $hub 配下のHIDデバイスが欠落しています。unbind/rebind を試します..."
echo "$hub" >/sys/bus/usb/drivers/usb/unbind
sleep 1
echo "$hub" >/sys/bus/usb/drivers/usb/bind
sleep 3

if [ "$(hid_count "$hub")" -ge 2 ]; then
  recovered "$hub"
  exit 0
fi

# ハブのsysfsパスを上に辿ってxhciコントローラのPCIアドレスを特定する
pci=""
p=$(readlink -f "/sys/bus/usb/devices/$hub")
while [ "$p" != "/" ]; do
  b=$(basename "$p")
  if [ -e "/sys/bus/pci/drivers/xhci_hcd/$b" ]; then
    pci=$b
    break
  fi
  p=$(dirname "$p")
done
if [ -z "$pci" ]; then
  echo "xhciコントローラを特定できませんでした。" >&2
  exit 1
fi

echo "効果なし。xhciコントローラ $pci をリセットします（同コントローラ配下の全USB機器が数秒切断されます）..."
echo "$pci" >/sys/bus/pci/drivers/xhci_hcd/unbind
sleep 2
echo "$pci" >/sys/bus/pci/drivers/xhci_hcd/bind
sleep 5

# コントローラリセットでバス番号が変わるため探し直す
hub=$(find_hub) || hub=""
if [ -n "$hub" ] && [ "$(hid_count "$hub")" -ge 2 ]; then
  recovered "$hub"
  exit 0
fi

echo "ホスト側からは復旧できませんでした。KVM内部ハブのハードハングです。" >&2
echo "モニタ (EV3895) の前面電源ボタンでオフ→オンしてください（Compatibility Modeオフの場合のみハブの電源が切れます）。" >&2
echo "それでも復旧しない場合は電源ケーブルを抜いて放置→再接続してください。" >&2
exit 1
