# =============================================================================
# cc-bar: Claude Code Context Window Monitor（COSMICパネルアプレット）
# =============================================================================
# このファイルは cc-bar 関連の全設定（システムパッケージ、
# Claude Code settings.json への hooks/statusLine 登録）を集約している。
#
# 無効化する場合:
#   flake.nix の modules リスト内 `./modules/cc-bar.nix` の行をコメントアウト
#   するだけで cc-bar 関連の全機能が無効になる。
#   （flake input と specialArgs の cc-bar 受け渡しは残っても無害）
# =============================================================================
{
  pkgs,
  cc-bar,
  ...
}:
let
  # 自作 flake のパッケージを直接参照する（cc-bar は nixpkgs を follows している）
  ccBar = cc-bar.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # COSMICパネル用 Claude Code コンテキストモニター本体
  environment.systemPackages = [ ccBar ];

  # Claude Code settings.json に statusLine と SubagentStop / SessionEnd hooks を設定
  # nixos-rebuild 時にスクリプトのパスを最新のNixストアパスに更新
  # lib.hm.dag は home-manager モジュール内でのみ利用可能なため
  # home-manager.users.tagawa をモジュール関数として渡す
  home-manager.users.tagawa = { lib, ... }: {
    home.activation.ccBarSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SETTINGS="$HOME/.claude/settings.json"
      if [ "''${DRY_RUN:-0}" != "1" ]; then
        # settings.json を新規作成（DRY_RUN 時はファイルシステムを変更しない）
        if [ ! -f "$SETTINGS" ]; then
          mkdir -p "$(dirname "$SETTINGS")"
          echo '{}' > "$SETTINGS"
        fi
        RELAY="${ccBar}/bin/cc-bar-relay.sh"
        HOOK="${ccBar}/bin/cc-bar-subagent-hook.sh"
        CLEANUP="${ccBar}/bin/cc-bar-session-cleanup.sh"
        # ensure_hook: event 配下に script（ファイル名で同定）の command hook を1つ保証する。
        # 既にあればパスだけ最新の Nix ストアパスに差し替え、無ければ末尾に追加する
        ${pkgs.jq}/bin/jq \
          --arg relay "$RELAY" \
          --arg hook "$HOOK" \
          --arg cleanup "$CLEANUP" \
          '
           def is_script($name): .type == "command" and (.command | tostring | contains($name));
           def ensure_hook($event; $script; $name):
             .hooks |= (
               . // {} |
               .[$event] |= (
                 ( . // [] ) as $arr
                 | if any($arr[]?.hooks[]?; is_script($name)) then
                     [ $arr[] | .hooks |= ((. // []) | map(if is_script($name) then .command = $script else . end)) ]
                   else
                     $arr + [ { "hooks": [ { "type": "command", "command": $script } ] } ]
                   end
               )
             );
           .statusLine |= (
             if (. == null or is_script("cc-bar-relay.sh")) then
               {"type": "command", "command": $relay}
             else
               .
             end
           )
           | ensure_hook("SubagentStop"; $hook; "cc-bar-subagent-hook.sh")
           | ensure_hook("SessionEnd"; $cleanup; "cc-bar-session-cleanup.sh")
          ' \
          "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
        echo "cc-bar: Claude Code settings updated"
      else
        $DRY_RUN_CMD echo "cc-bar: (dry run) Claude Code settings would be updated"
      fi
    '';
  };
}
