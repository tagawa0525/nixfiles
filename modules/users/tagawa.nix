# =============================================================================
# tagawa ユーザー定義（システムレベル）
# =============================================================================
# tagawa を住人として持つホストは hosts/<name>/default.nix の imports に
# ../../modules/users/tagawa.nix を追加してください。
# workstation profile を import するホストでは、追加で libvirtd グループも
# workstation.nix 経由で付与されます。
# ホスト依存しない権限・パスワードハッシュ・rootless container 用 sub UID/GID は
# 本ファイルに集約します。
# home-manager 側（dotfiles, shell, editors 等）は
# modules/home/users/tagawa/default.nix を参照してください。
# =============================================================================
{ pkgs, ... }:

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
    # libvirtd は workstation.nix（virt-manager/libvirtd を有効化する側）で追加する
    extraGroups = [
      "wheel"
      "networkmanager"
      "podman"
    ];
    # mkpasswd -m sha-512 で生成したハッシュ
    hashedPassword = "$6$g8T1ZyjV8uoBKzcp$HPjF9mnYkkpEyY3NXeK1HXv.Y3vcUSN4bHkzktlzuSi9SHxBYcNbbhtfwYHMSw5gQ2spy8fF9MORT.oUOUboA.";
    shell = pkgs.bash; # デフォルトはbash（VSCode-Server等の互換性のため）
  };
}
