# =============================================================================
# Delta（Zed 開発元の AI ネイティブエディタ）を NixOS で動かすための下駄
# =============================================================================
# Delta は早期アクセス配布で、ダウンロードに Zed アカウントのセッション Cookie が
# 必須（未認証は 401）なため fetchurl できず、Nix パッケージ化していない。
# 本体は公式手順どおり tarball を展開して install.sh を実行し、
# ~/.local/delta.app に置いて内蔵の AutoUpdater に更新を任せる。
#
#   tar -xzf delta-linux-x86_64.tar.gz && ./Delta/install.sh
#
# このファイルに置くのは「FHS 非準拠の NixOS だから必要になる」OS 側の設定だけ。
# 使わなくなったら modules/profiles/workstation.nix の import 行と本ファイルを
# 消せばシステム側に痕跡は残らない（~/.local/delta.app と ~/.local/bin/delta、
# ~/.local/share/applications/dev.zed.Delta.desktop の削除は手動）。
{ pkgs, ... }:

{
  # ===========================================================================
  # nix-ld: 配布バイナリが dlopen する共有ライブラリ
  # ===========================================================================
  # base プロファイルの nix-ld は CLI/サーバ系バイナリ向けの最小構成なので、
  # GPU とウィンドウシステムを直接叩く分だけここで補う。
  # 追加は Delta が実際に dlopen する soname に絞ってある。libxcb /
  # libxkbcommon / libunwind は tarball の Delta/lib に同梱され
  # RPATH=$ORIGIN/../lib で解決され、fontconfig は静的リンクされている。
  programs.nix-ld.libraries = with pkgs; [
    vulkan-loader # libvulkan.so.1（wgpu の Vulkan バックエンド）
    libglvnd # libEGL.so.1（Vulkan 不可時の GLES フォールバック）
    wayland # libwayland-client.so.0, libwayland-egl.so.1
  ];

  # ===========================================================================
  # 同梱 libxkbcommon の XKB データ探索先
  # ===========================================================================
  # 同梱版はビルド時の既定パス /usr/share/X11/xkb を参照するため、NixOS では
  # 「libxkbcommon failed to create an XKB context」で失敗し、gpui の Wayland
  # キーマップ処理が unwrap で panic してウィンドウが開かない。
  # 配布物は RPATH により nixpkgs 版より同梱版を優先して掴むので nix-ld では
  # 差し替えられず、環境変数で正しい場所を教えるしかない。
  # nixpkgs の libxkbcommon も同じ xkeyboard_config を既定値に持つため、
  # Nix 製アプリにとっては既定値の明示と等価で影響しない。
  environment.sessionVariables.XKB_CONFIG_ROOT = "${pkgs.xkeyboard_config}/etc/X11/xkb";
}
