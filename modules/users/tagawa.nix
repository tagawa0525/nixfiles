# =============================================================================
# tagawa ユーザー定義
# =============================================================================
# tagawa を住人として持つホストは hosts/<name>/default.nix の imports に
# ../../modules/users/tagawa.nix を追加してください。
# このファイル1つで以下が揃う（ホスト側に他の編集は不要）:
#   - システムユーザー（権限・パスワードハッシュ・rootless container 用 sub UID/GID）
#   - SSH authorized_keys（../home/users/tagawa/keys/*.pub を自動集約）
#   - Home Manager 設定（dotfiles, shell, editors 等）の紐付け
# workstation profile を import するホストでは、追加で libvirtd グループも
# 条件付きで付与されます。
#
# authorized_keys は users.users.<name>.openssh.authorizedKeys.keyFiles 経由で
# /etc/ssh/authorized_keys.d/<name> に書き出される。home-manager で
# ~/.ssh/authorized_keys を nix store への symlink にすると sshd の
# StrictModes が "bad ownership or modes" で認証拒否するため、この方式を使う。
# 新ホスト追加時は keys/ に <hostName>.pub を置くだけで反映される。
# =============================================================================
{ config, lib, pkgs, ... }:

let
  keysDir = ../home/users/tagawa/keys;
  # keys/ 未作成でも評価を壊さない（新ユーザーのブートストラップ中は鍵なし扱い）
  authorizedKeyFiles =
    if builtins.pathExists keysDir then
      map (n: keysDir + "/${n}")
        (builtins.filter (lib.hasSuffix ".pub")
          (builtins.attrNames (builtins.readDir keysDir)))
    else [ ];
in
{
  users.users.tagawa = {
    isNormalUser = true;
    # Rootlessコンテナ用のサブUID/GID範囲を割り当て
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
    # wheel: sudo権限, networkmanager: WiFi操作, podman: コンテナ操作
    # libvirtd は workstation profile で virtualisation.libvirtd が有効化された
    # ホストでのみ追加する（profile 側に username を書かないため）
    extraGroups = [
      "wheel"
      "networkmanager"
      "podman"
    ] ++ lib.optionals config.virtualisation.libvirtd.enable [ "libvirtd" ];
    # パスワードは宣言しない（public リポジトリにハッシュを置かないため）。
    # users.mutableUsers = true（デフォルト）のため /etc/shadow は passwd で
    # 管理され、rebuild で上書きされない。新ホストではユーザーがパスワード
    # ロック状態で作られるので、初回起動時に root で `passwd tagawa` を実行する
    # （SSH は authorized_keys で入れるが sudo にはパスワードが必要）。
    shell = pkgs.bash; # デフォルトはbash（VSCode-Server等の互換性のため）
    openssh.authorizedKeys.keyFiles = authorizedKeyFiles;
  };

  # Home Manager 設定（このユーザーが住むホストにのみ適用される）
  home-manager.users.tagawa = import ../home/users/tagawa/default.nix;
}
