# =============================================================================
# handlr-regex: shared-mime-info 2.5 系でテストが落ちる問題のパッチ
# =============================================================================
# handlr-regex 0.13.0 のテストは tests/assets/cat（シェルスクリプト）の MIME を
# application/x-shellscript と決め打ちしている。shared-mime-info 2.5.1 は
# text/x-shellscript と判定するため checkPhase が失敗し、nix-rebuild update の
# 検証ゲートで flake.lock が巻き戻され続ける（更新が全面的に止まる）。
# 実行時の MIME 判定自体は問題なく、テストの期待値だけが古い。
#
# パッチは期待値を実際の判定値へ厳密に更新するもの（テストは無効化しない）。
# 生成は shared-mime-info 2.5.1 の環境で insta に snapshot を更新させた差分。
#
# 撤去する場合:
#   上流（handlr-regex / nixpkgs）が期待値を修正して nixpkgs に入ったら、
#   flake.nix の import 行と本ファイル、modules/patches/handlr-regex-*.patch を削除する。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = [
    (_final: prev: {
      handlr-regex = prev.handlr-regex.overrideAttrs (old: {
        # 2.4 以前は旧来の期待値が正しいので、2.5 以上のときだけ当てる
        patches =
          (old.patches or [ ])
          ++ lib.optional (lib.versionAtLeast prev.shared-mime-info.version "2.5") ./patches/handlr-regex-shared-mime-info-2.5.patch;
      });
    })
  ];
}
