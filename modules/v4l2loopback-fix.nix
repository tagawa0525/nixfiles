# =============================================================================
# v4l2loopback: depmod の生成物を出力から除く
# =============================================================================
# kernel 7.3 では `make modules_install` が depmod を内部で実行するため、
# nixpkgs のパッケージが Makefile から depmod 行を消しても modules.alias などが
# 出力に残る。kernel の modules ツリー (linux-*-modules) は
# buildEnv で全モジュールパッケージを重ねるので、同名の modules.alias が
# kernel 側と衝突してビルドが失敗する。
# depmod の生成物は buildEnv の後に kernel 側で作り直されるため、不要である。
#
# 撤去する場合:
#   nixpkgs の v4l2loopback が出力から modules.* を除くようになったら、
#   modules/profiles/workstation.nix の import 行と本ファイルを削除する。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      linuxPackages_latest = prev.linuxPackages_latest.extend (
        _kfinal: kprev: {
          v4l2loopback = kprev.v4l2loopback.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              rm -f $out/lib/modules/*/modules.*
            '';
          });
        }
      );
    })
  ];
}
