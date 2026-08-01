# =============================================================================
# nix-rebuild の switch をパスワードなしで許可する
# =============================================================================
# nix-rebuild.sh の nixos_rebuild_switch() が発行する固定コマンド行
# （引数まで完全一致）に限り NOPASSWD を許可する。
#
# 動機:
#   - 自動更新（modules/nix-auto-update.nix）は systemd user service なので
#     パスワード入力の機会がなく、これがないと成立しない
#   - 対話実行のホストでは必然ではなく利便のための受容。rebuild / update の
#     たびのパスワード入力を省く。ホストごとに挙動が違う方が事故を生むため、
#     tagawa が住む全ホストに一様に適用する
#
# 効果の範囲:
#   コマンド行を固定しているので、任意のコマンドや任意の flake を指定した
#   即時 root 化には使えない。`--flake .` のような cwd 依存の形を許可すると
#   この性質が失われる（sudo は cwd を制約できない）ため、nix-rebuild.sh 側は
#   絶対パスに固定してある。
#
# 残存リスク:
#   参照先の ~/nix/nixfiles は tagawa が書き込めるため、セッションを掌握した
#   攻撃者は構成を書き換えることで次回の rebuild / update 時に root を取れる。
#   「ユーザーが書ける構成を root 権限で適用する」仕組みに固有のリスクで、
#   sudo の絞り込みでは除去できない（即時のオンデマンド root 化を防ぐ
#   ところまでが効果）。除去するにはリポジトリを root 所有に移し、自動更新も
#   system service にしたうえで push 用の秘密鍵を root 側に置く必要がある。
#   現状は受容する。
#
# 適用範囲:
#   modules/users/tagawa.nix から import している。ルールがこのユーザーに
#   紐づくため、tagawa が住むホストにだけ入るのが正しいスコープになる。
# =============================================================================
let
  user = "tagawa";
  # nix-rebuild.sh の NIXDIR と一致していること（片方だけ変えると sudoers に
  # 一致しなくなり、パスワードを入力できない user service で失敗する）
  nixdir = "/home/${user}/nix/nixfiles";
in
{
  security.sudo.extraRules = [
    {
      users = [ user ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild switch --flake ${nixdir}";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
