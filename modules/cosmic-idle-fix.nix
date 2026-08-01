# =============================================================================
# cosmic-idle: AC/バッテリー切り替えを自動サスペンドに反映させるパッチ
# =============================================================================
# 上流 cosmic-idle は UPower の OnBattery 変化を受け取ってもサスペンド用の
# idle notification を作り直さない。そのため AC 接続状態で起動すると
# on_battery = false のまま固定され、「コンセント接続時の自動サスペンド: しない」
# を設定していると以後バッテリー駆動になっても自動サスペンドが発火しない。
#
# x1ng1 では実際にこれが発生し、蓋を開けたまま放置した 7 時間 15 分の間
# 一度もサスペンドせず 60% → 17% まで消費した（調査記録は
# docs/x1ng1-power-management.md を参照）。
#
# 上流は epoch-1.5.0 / master (c95d066b) 時点で未修正、修正 PR もない。
# コード実体の最終更新は 2025-10-05 で事実上停止しているため、
# nixpkgs の追従では解決せず overlay でパッチを当てる。
#
# 撤去する場合:
#   上流に修正が入ったら modules/profiles/laptop.nix の import 行を削除し、
#   本ファイルと modules/patches/ 配下のパッチを削除する。
#
# cosmic-idle は他パッケージから参照されない末端バイナリで Cargo.lock も
# 変更しないため、再ビルドは cosmic-idle 単体のみ（cargoHash の追従も不要）。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      cosmic-idle = prev.cosmic-idle.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/cosmic-idle-recreate-notifications-on-battery.patch
        ];
      });
    })
  ];
}
