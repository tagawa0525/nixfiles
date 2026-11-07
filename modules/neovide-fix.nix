# =============================================================================
# neovide: 0.17.1 の src / cargoHash を直ったハッシュに差し替える
# =============================================================================
# nixpkgs 6dadaf43 の neovide 0.17.1 は src.hash と cargoHash が誤った同一の値で、
# vendor-staging が Cargo.lock なしで失敗する（NixOS/nixpkgs#583658 で修正済み）。
# 下の 2 つは、その修正（2cc8df229）と同じ値。
# cargoHash は finalAttrs 経由で cargoDeps に渡るので、overrideAttrs では
# cargoDeps を作り直す必要がある。
#
# 撤去する場合:
#   nixpkgs-unstable が 2cc8df229 以降に進んだら、flake.nix の import 行と
#   本ファイルを削除する（確認: gh api repos/NixOS/nixpkgs/compare/2cc8df229...nixpkgs-unstable
#   の status が ahead か identical）。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (final: prev: {
      neovide = prev.neovide.overrideAttrs (old: rec {
        src = old.src.overrideAttrs (_: {
          outputHash = "sha256-trl/YctM/E9vIXeJfwBEZLfNK7LS5fEaWthTbeg7Ba0=";
        });
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit src;
          hash = "sha256-WS44afUizU6qhXQY77TayNRvlUoS6GrBZ/uaXk+gjU0=";
        };
      });
    })
  ];
}
