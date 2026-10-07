# =============================================================================
# gcc 16 でテストが落ちる zat の暫定対処
# =============================================================================
# nixpkgs が gcc 15 → 16 に上がった更新（glibc 2.42 → 2.44 と同時）で、zat の
# checkPhase が落ち、nix-rebuild update の検証ゲートで flake.lock が巻き戻される。
# テストは無効化せず、原因に即した最小の修正を当てる。
#
#   - zat: test_haskell が "corrupted size vs. prev_size" で SIGABRT。
#     tree-sitter-haskell 0.23.1 が同梱する旧 array.h は、別の構造体型へキャストして
#     contents を更新した後に元の型で読む（strict aliasing 違反）。gcc 16 は realloc 後の
#     新しいポインタを読み直さず、解放済みブロックへ書く（valgrind で確認）。
#     tree-sitter-haskell 0.24.0 で array.h が修正済みなので、根本対処は zat 側の依存更新
#     （bglgwyng/zat#3）。それが nixpkgs に入るまで -fno-strict-aliasing で回避する。
#
# 撤去する場合:
#   上流が tree-sitter-haskell 0.24 以上へ更新した zat が nixpkgs に入った時に、
#   flake.nix の import 行と本ファイルを削除する。
# =============================================================================
_: {
  nixpkgs.overlays = [
    (_final: prev: {
      zat = prev.zat.overrideAttrs (old: {
        env = (old.env or { }) // {
          CFLAGS = "-fno-strict-aliasing";
        };
      });
    })
  ];
}
