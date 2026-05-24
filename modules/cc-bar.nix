# =============================================================================
# cc-bar: Claude Code Context Window Monitor（COSMICパネルアプレット）
# =============================================================================
# このファイルは cc-bar 関連の全設定（overlay、システムパッケージ、
# Claude Code settings.json への hooks/statusLine 登録）を集約している。
#
# 無効化する場合:
#   flake.nix の modules リスト内 `./modules/cc-bar.nix` の行をコメントアウト
#   するだけで cc-bar 関連の全機能が無効になる。
#   （flake input と specialArgs の cc-bar 受け渡しは残っても無害）
# =============================================================================
{ pkgs, lib, cc-bar, ... }:
{
  # nixpkgs に cc-bar overlay を追加し pkgs.cc-bar として参照可能にする。
  # 元の flake.nix では overlays 配列の末尾に置かれていた（後勝ち）。
  # 本モジュールが他の overlay より前に評価されても末尾相当の優先度を
  # 維持できるよう lib.mkAfter を使う。
  nixpkgs.overlays = lib.mkAfter [ cc-bar.overlays.default ];

  # COSMICパネル用 Claude Code コンテキストモニター本体
  environment.systemPackages = [ pkgs.cc-bar ];

  # Claude Code settings.json に statusLine と SubagentStop hooks を設定
  # nixos-rebuild 時にスクリプトのパスを最新のNixストアパスに更新
  # lib.hm.dag は home-manager モジュール内でのみ利用可能なため
  # home-manager.users.tagawa をモジュール関数として渡す
  home-manager.users.tagawa = { lib, ... }: {
    home.activation.ccBarSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SETTINGS="$HOME/.claude/settings.json"
      # Create settings file if it doesn't exist
      if [ ! -f "$SETTINGS" ]; then
        mkdir -p "$(dirname "$SETTINGS")"
        echo '{}' > "$SETTINGS"
      fi
      if [ -f "$SETTINGS" ]; then
        if [ "''${DRY_RUN:-0}" != "1" ]; then
          RELAY="${pkgs.cc-bar}/bin/cc-bar-relay.sh"
          HOOK="${pkgs.cc-bar}/bin/cc-bar-subagent-hook.sh"
          ${pkgs.jq}/bin/jq \
            --arg relay "$RELAY" \
            --arg hook "$HOOK" \
            '.statusLine |= (
               if (. == null or (.type == "command" and (.command | tostring | contains("cc-bar-relay.sh")))) then
                 {"type": "command", "command": $relay}
               else
                 .
               end
             ) |
             .hooks |= (
               . // {} |
               .SubagentStop |= (
                 ( . // [] ) as $arr
                 | ( any( $arr[]?.hooks[]?; .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh")) ) ) as $hasCcBar
                 | if $hasCcBar then
                     [ $arr[] |
                       if any(.hooks[]?; .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh"))) then
                         .hooks |= (
                           (.hooks // []) |
                           map(
                             if .type == "command" and (.command | tostring | contains("cc-bar-subagent-hook.sh")) then
                               .command = $hook
                             else
                               .
                             end
                           )
                         )
                       else
                         .
                       end
                     ]
                   else
                     $arr + [ { "hooks": [ { "type": "command", "command": $hook } ] } ]
                   end
               )
             )' \
            "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
          echo "cc-bar: Claude Code settings updated"
        else
          $DRY_RUN_CMD echo "cc-bar: (dry run) Claude Code settings would be updated"
        fi
      fi
    '';
  };
}
