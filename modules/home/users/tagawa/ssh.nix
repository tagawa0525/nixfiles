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
  # ./keys/ ディレクトリ内の全 .pub ファイルを動的に取得
  # 新しいホストの公開鍵を追加するだけで、自動的に authorized_keys に反映
  keysDir = ./keys;
  keyFiles = map
    (name: keysDir + "/${name}")
    (builtins.filter
      (name: lib.hasSuffix ".pub" name)
      (builtins.attrNames (builtins.readDir keysDir)));
in
{
  # ===========================================================================
  # authorized_keys（個人設定で管理）
  # ===========================================================================
  # 複数ホスト間のSSH接続を可能にするため、すべての公開鍵を登録
  # home.file は Nix store への symlink として配置される。
  # symlink 先（Nix store）のファイルは read-only (444) のため、
  # OpenSSH の認証要件（group/other に書き込み権限なし）を満たす。
  home.file.".ssh/authorized_keys" = {
    text = builtins.concatStringsSep "\n"
      (map (keyFile: lib.removeSuffix "\n" (builtins.readFile keyFile))
        keyFiles) + "\n";
    executable = false;
  };
}
