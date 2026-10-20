#!/usr/bin/env bash
# nix-update-hash.sh — Nix パッケージの固定出力ハッシュ（cargoHash など）を更新する
#
# Usage: nix-update-hash.sh [-C <dir>] [-a <attr>] <package> <file>
#
#   -C <dir>   <dir> の flake で実行する（既定: 今いる場所）
#   -a <attr>  更新する属性（既定: cargoHash）。vendorHash、npmDepsHash など
#   <package>  nix build .#<package> のパッケージ名
#   <file>     <attr> = "..."; を含む Nix ファイル
#
# 手順: <attr> をダミーのハッシュに差し替え → nix build → ログの "got: sha256-..." を取り出す →
# 書き込み → もう一度 nix build して終了コードを確かめる。ビルドの出力はパイプに通さない
# （終了コードが消え、空の取り出しや失敗したビルドを成功と取り違えるため）。
#
# 取り出せなかったとき、再ビルドが失敗したときは、ログの場所を出して失敗する。
# ハッシュを取れなかったときはファイルを元に戻す。
#
# 出力: 成功時に新しいハッシュを 1 行（stdout）。進行は stderr。

set -euo pipefail

DUMMY="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
attr="cargoHash"
dir="."

while getopts "C:a:" opt; do
  case "$opt" in
    C) dir="$OPTARG" ;;
    a) attr="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -eq 2 ] || { echo "Usage: $0 [-C <dir>] [-a <attr>] <package> <file>" >&2; exit 2; }
package="$1"
file="$2"

cd "$dir"
[ -f "$file" ] || { echo "ERROR: $file がない" >&2; exit 1; }

pattern="(${attr}[[:space:]]*=[[:space:]]*)\"[^\"]*\""
[ "$(grep -cE "$pattern" "$file")" -eq 1 ] || {
  echo "ERROR: $file に $attr = \"...\" の行が 1 つだけでない" >&2
  exit 1
}

backup=$(mktemp)
log=$(mktemp)
cp "$file" "$backup"
trap 'rm -f "$backup"' EXIT

set_hash() {
  sed -E -i "s|${pattern}|\\1\"$1\"|" "$file"
}

set_hash "$DUMMY"
echo "RUN: nix build --no-link .#${package}（ダミーのハッシュ）" >&2
# ダミーのハッシュなので失敗するのが正。終了コードでなく、ログの got: で判断する
nix build --no-link ".#${package}" >"$log" 2>&1 || true

hash=$(grep -oE 'got:[[:space:]]+sha256-[A-Za-z0-9+/]+=*' "$log" | head -n 1 | sed -E 's/^got:[[:space:]]+//' || true)
if [ -z "$hash" ]; then
  cp "$backup" "$file"
  echo "ERROR: ログに got: sha256-... がない（$file は元に戻した）。ログ: $log" >&2
  exit 1
fi

set_hash "$hash"
echo "RUN: nix build --no-link .#${package}（$attr = $hash）" >&2
if ! nix build --no-link ".#${package}" >"$log" 2>&1; then
  echo "ERROR: ハッシュを書き込んだ後のビルドが失敗した。ログ: $log" >&2
  exit 1
fi

echo "$hash"
