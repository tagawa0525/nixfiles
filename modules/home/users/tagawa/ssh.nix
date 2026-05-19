# =============================================================================
# SSH設定（tagawa ユーザー専用）
# =============================================================================
# t14g4（ラップトップ）で単一ユーザー（tagawa）が管理する authorized_keys。
# 複数ホスト間（t14g4 ↔ r995）の相互接続用公開鍵を登録。
#
# 注：r995（server）は複数ユーザーを想定しているため、
#    system設定で各ユーザーの authorized_keys を定義。
# =============================================================================
{ lib, ... }:

let
  keyFiles = [
    ./keys/t14g4.pub
    ./keys/r995.pub
  ];
in
{
  # ===========================================================================
  # authorized_keys（個人設定で管理）
  # ===========================================================================
  # 複数ホスト間のSSH接続を可能にするため、すべての公開鍵を登録
  home.file.".ssh/authorized_keys" = {
    text = builtins.concatStringsSep "\n"
      (map (keyFile: lib.removeSuffix "\n" (builtins.readFile keyFile))
        keyFiles) + "\n";
    executable = false;
  };

  # authorized_keys のパーミッション設定（SSH は600を要求）
  home.activation.fixAuthorizedKeysPermissions =
    lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      chmod 600 $HOME/.ssh/authorized_keys 2>/dev/null || true
    '';
}
