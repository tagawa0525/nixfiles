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
  # user service にはパスワード入力の機会がないため、nixos-rebuild に限り
  # パスワードなし sudo を許可する。tagawa は wheel なので任意コマンドを
  # パスワード付きで実行できる状態は変わらず、免除対象が1コマンド増えるだけ
  security.sudo.extraRules = [
    {
      users = [ "tagawa" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.user.services.nix-auto-update = {
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

  systemd.user.services.nix-auto-update-notify = {
    description = "Notify user of nix-auto-update failure";
    unitConfig.ConditionUser = "tagawa";
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.libnotify}/bin/notify-send --urgency=critical \
        "NixOS 自動更新に失敗しました" \
        "journalctl --user -u nix-auto-update.service で確認してください"
    '';
  };

  systemd.user.timers.nix-auto-update = {
    description = "Daily NixOS auto update";
    unitConfig.ConditionUser = "tagawa";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:30:00";
      Persistent = true;
    };
  };
}
