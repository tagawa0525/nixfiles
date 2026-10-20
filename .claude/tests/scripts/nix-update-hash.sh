#!/usr/bin/env bash
# language-checks/scripts/nix-update-hash.sh のテスト
#
# 実行: bash .claude/tests/scripts/nix-update-hash.sh（まとめて実行: bash .claude/tests/scripts.sh）
#
# 実物の nix は使わず、PATH 先頭に置いた偽の nix で「ダミーのハッシュ → got: の取り出し →
# 書き込み → 再ビルドの終了コード」の流れを検証する。

source "$(dirname "$0")/../lib.sh"

LANG_SCRIPTS="$CLAUDE_DIR/skills/language-checks/scripts"


HASH_DIR="$TEST_ROOT/nixhash"
mkdir -p "$HASH_DIR" "$TEST_ROOT/hashbin"
OLD_HASH="sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLD="
NEW_HASH="sha256-NEWNEWNEWNEWNEWNEWNEWNEWNEWNEWNEWNEWNEWNEW="
DUMMY_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# 偽の nix: package.nix の cargoHash が NEW なら成功、ダミーなら got: 付きで失敗する。
# FAKE_NIX_MODE=nogot はハッシュ不一致以外の理由で失敗、FAKE_NIX_MODE=final-fail は書き込み後も失敗する
cat > "$TEST_ROOT/hashbin/nix" <<FAKE
#!/usr/bin/env bash
echo "\$*" >> "$TEST_ROOT/nix.log"
if grep -q '$NEW_HASH' package.nix; then
  [ "\${FAKE_NIX_MODE:-}" = final-fail ] && { echo "error: build failed" >&2; exit 1; }
  echo "built"; exit 0
fi
if [ "\${FAKE_NIX_MODE:-}" = nogot ]; then echo "error: syntax error" >&2; exit 1; fi
echo "error: hash mismatch in fixed-output derivation"
echo "  specified: $DUMMY_HASH"
echo "     got:    $NEW_HASH"
exit 1
FAKE
chmod +x "$TEST_ROOT/hashbin/nix"

reset_pkg() {
  printf '{\n  pname = "x";\n  cargoHash = "%s";\n  npmDepsHash = "%s";\n}\n' "$OLD_HASH" "$OLD_HASH" > "$HASH_DIR/package.nix"
  : > "$TEST_ROOT/nix.log"
}

it "nix-update-hash: ダミーのハッシュでビルドして got: を取り出し、cargoHash を書き換えて再ビルドし、新しいハッシュを出力する"
reset_pkg
out=$(cd "$HASH_DIR" && PATH="$TEST_ROOT/hashbin:$PATH" "$LANG_SCRIPTS/nix-update-hash.sh" mypkg package.nix 2>/dev/null)
assert_eq 0 $?
assert_contains "$out" "$NEW_HASH"
assert_eq $'build --no-link .#mypkg\nbuild --no-link .#mypkg' "$(cat "$TEST_ROOT/nix.log")"
assert_contains "$(cat "$HASH_DIR/package.nix")" "cargoHash = \"$NEW_HASH\""
assert_contains "$(cat "$HASH_DIR/package.nix")" "npmDepsHash = \"$OLD_HASH\""

it "nix-update-hash: 属性名を指定すればその属性だけを更新する"
reset_pkg
(cd "$HASH_DIR" && PATH="$TEST_ROOT/hashbin:$PATH" "$LANG_SCRIPTS/nix-update-hash.sh" -a npmDepsHash mypkg package.nix >/dev/null 2>&1)
assert_contains "$(cat "$HASH_DIR/package.nix")" "npmDepsHash = \"$NEW_HASH\""
assert_contains "$(cat "$HASH_DIR/package.nix")" "cargoHash = \"$OLD_HASH\""

it "nix-update-hash: ログに got: が無ければ失敗し、ファイルを元に戻す"
reset_pkg
(cd "$HASH_DIR" && FAKE_NIX_MODE=nogot PATH="$TEST_ROOT/hashbin:$PATH" "$LANG_SCRIPTS/nix-update-hash.sh" mypkg package.nix >/dev/null 2>&1)
assert_eq 1 $?
assert_contains "$(cat "$HASH_DIR/package.nix")" "cargoHash = \"$OLD_HASH\""

it "nix-update-hash: 書き込み後の再ビルドが失敗したら終了コードが非 0 になる"
reset_pkg
(cd "$HASH_DIR" && FAKE_NIX_MODE=final-fail PATH="$TEST_ROOT/hashbin:$PATH" "$LANG_SCRIPTS/nix-update-hash.sh" mypkg package.nix >/dev/null 2>&1)
assert_eq 1 $?

it "nix-update-hash: 属性がファイルに無ければ失敗し、nix を呼ばない"
reset_pkg
(cd "$HASH_DIR" && PATH="$TEST_ROOT/hashbin:$PATH" "$LANG_SCRIPTS/nix-update-hash.sh" -a vendorHash mypkg package.nix >/dev/null 2>&1)
assert_eq 1 $?
assert_eq "" "$(cat "$TEST_ROOT/nix.log")"

finish
