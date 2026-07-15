# =============================================================================
# NixOS 自動更新（常時稼働のデスクトップ機用）
# =============================================================================
# nix-rebuild update を毎朝 systemd user timer で実行する。
#
# 設計:
#   - 実行時刻は使用開始直前の早朝。更新直後に自分が使い始めることで、
#     ビルドは通るがランタイムが壊れているケースに最短で気づける
#   - update は全ホストのビルド検証を通ってから flake.lock を push する
#     （modules/home/scripts/nix-rebuild.sh 参照）。壊れた lock が
#     他ホストに伝播することをビルドレベルで防ぐ
#   - Persistent=true により電源が入っていなかった日の分は次回
#     ログイン時に実行される
#   - 失敗時はデスクトップ通知（OnFailure）。自動化の静かな劣化を防ぐ
#
# 前提:
#   - ~/.local/bin/nix-rebuild が存在する（modules/home/parts/shell.nix）
#   - git push 用の SSH 鍵がパスフレーズなし、または agent で解錠済み
# =============================================================================
{ pkgs, ... }:

{
  # user service にはパスワード入力の機会がないため、nix-rebuild.sh が
  # 発行する固定コマンド行（引数まで完全一致）に限り NOPASSWD を許可する。
  # 任意の flake を指定した即時 root 化には使えない。
  #
  # 残存リスク: 参照先の ~/nix/nixfiles は tagawa が書き込めるため、
  # セッションを掌握した攻撃者は構成を書き換えることで次回実行時に root を
  # 取れる。これは「ユーザー所有の構成を root 権限で自動適用する」仕組みに
  # 固有のリスクで、sudo の絞り込みでは除去できない（即時のオンデマンド
  # root 化を防ぐところまでが効果）。受容する
  security.sudo.extraRules = [
    {
      users = [ "tagawa" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild switch --flake /home/tagawa/nix/nixfiles";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.user = {
    services = {
      nix-auto-update = {
        description = "NixOS flake update (verify all hosts, switch, push)";
        # cosmic-greeter 等の他ユーザーの user manager では起動しない
        unitConfig.ConditionUser = "tagawa";
        onFailure = [ "nix-auto-update-notify.service" ];
        # sudo は setuid wrapper (/run/wrappers) が必須。git / nix /
        # nixos-rebuild / hostname は systemPackages から解決する
        path = [
          "/run/wrappers"
          "/run/current-system/sw"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "%h/.local/bin/nix-rebuild update";
        };
      };

      nix-auto-update-notify = {
        description = "Notify user of nix-auto-update failure";
        unitConfig.ConditionUser = "tagawa";
        serviceConfig.Type = "oneshot";
        script = ''
          ${pkgs.libnotify}/bin/notify-send --urgency=critical \
            "NixOS 自動更新に失敗しました" \
            "journalctl --user -u nix-auto-update.service で確認してください"
        '';
      };
    };

    timers.nix-auto-update = {
      description = "Daily NixOS auto update";
      unitConfig.ConditionUser = "tagawa";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 06:30:00";
        Persistent = true;
      };
    };
  };
}
