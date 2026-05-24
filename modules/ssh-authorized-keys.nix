# =============================================================================
# SSH authorized_keys (NixOS system 設定)
# =============================================================================
# 各ユーザーの authorized_keys を NixOS 側で管理する。
#
# 以前は home-manager で ~/.ssh/authorized_keys を nix store への symlink
# として配置していたが、sshd の StrictModes が symlink 先のパス階層
# (/nix/store, group 書き込み可) を問題視し、
#   "Authentication refused: bad ownership or modes for directory /nix/store"
# で認証が拒否される問題があった。
#
# users.users.<name>.openssh.authorizedKeys.keyFiles を使うと
# /etc/ssh/authorized_keys.d/<name> に書き出されるため、この問題を回避できる
# (sshd_config の AuthorizedKeysFile に既に登録済み)。
#
# 鍵ソース: modules/home/users/<userName>/keys/*.pub
#   - <userName> ごとに keys/ 配下の全 .pub をそのユーザーの authorized_keys に登録
#   - 新ホスト追加時は同ディレクトリに <hostName>.pub を置くだけで反映
#   - 新ユーザー追加時は modules/home/users/<newuser>/keys/ を作って .pub を置く
# =============================================================================
{ lib, ... }:

let
  usersDir = ./home/users;

  listPubs = dir:
    if builtins.pathExists dir then
      map (n: dir + "/${n}")
        (builtins.filter (n: lib.hasSuffix ".pub" n)
          (builtins.attrNames (builtins.readDir dir)))
    else [ ];

  # keys/ ディレクトリを持つユーザーだけを対象にする
  userNames = builtins.filter
    (n: builtins.pathExists (usersDir + "/${n}/keys"))
    (builtins.attrNames (builtins.readDir usersDir));
in
{
  users.users = lib.genAttrs userNames (userName: {
    openssh.authorizedKeys.keyFiles = listPubs (usersDir + "/${userName}/keys");
  });
}
