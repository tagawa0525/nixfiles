# =============================================================================
# gcc 16 でテストが落ちる zat / ltrace の暫定対処
# =============================================================================
# nixpkgs が gcc 15 → 16 に上がった更新（glibc 2.42 → 2.44 と同時）で、次の 2 つの
# checkPhase が落ち、nix-rebuild update の検証ゲートで flake.lock が巻き戻される。
# どちらもテストは無効化せず、原因に即した最小の修正を当てる。
#
#   - zat: test_haskell が "corrupted size vs. prev_size" で SIGABRT。
#     tree-sitter-haskell 0.23.1 が同梱する旧 array.h は、別の構造体型へキャストして
#     contents を更新した後に元の型で読む（strict aliasing 違反）。gcc 16 は realloc 後の
#     新しいポインタを読み直さず、解放済みブロックへ書く（valgrind で確認）。
#     tree-sitter-haskell 0.24.0 で array.h が修正済みなので、根本対処は zat 側の依存更新
#     （bglgwyng/zat#3）。それが nixpkgs に入るまで -fno-strict-aliasing で回避する。
#   - ltrace: demangle.exp のテスト用 C++ が gcc 16 の
#     "'volatile'-qualified return type is deprecated" 警告でコンパイルできず 15 件失敗。
#     戻り値の volatile はマングル名に含まれずテスト内容に影響しないため外す
#     （上流 cespedes/ltrace!112。マージ後に nixpkgs へ取り込まれるまでの暫定）。
#
# 撤去する場合:
#   zat は上流が tree-sitter-haskell 0.24 以上へ更新した版が nixpkgs に入った時、
#   ltrace は nixpkgs 側で同等の修正が入った時に、該当する overlay を削除する。
#   両方不要になったら flake.nix の import 行と本ファイルを削除する。
# =============================================================================
_: {
  nixpkgs.overlays = [
    (_final: prev: {
      zat = prev.zat.overrideAttrs (old: {
        env = (old.env or { }) // {
          CFLAGS = "-fno-strict-aliasing";
        };
      });
      ltrace = prev.ltrace.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace testsuite/ltrace.minor/demangle.cpp testsuite/ltrace.minor/demangle-lib.cpp \
            --replace-fail "volatile int Fv_Vi" "int Fv_Vi"
        '';
      });
    })
  ];
}
