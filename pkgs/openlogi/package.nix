# =============================================================================
# OpenLogi (Logitech Options+ 代替) の Linux パッケージ
# =============================================================================
# fork (tagawa0525/OpenLogi) を flake input `openlogi-src` から取り込んでビルド
# する。nixpkgs の `openlogi` と upstream の nix/package.nix はどちらも
# macOS 専用（.app バンドルを作る installPhase、platforms = darwin）で Linux
# 出力を持たないため、この定義は流用ではなく新規に書いている。
#
# upstream は自前 flake を #262 で削除した。理由は fetchCargoVendor の単一
# cargoHash が Cargo.lock の変更ごとに無効化されること（ローカルクレートの
# バージョンが lock に埋まるため、リリースのたびに再計算が必要だった）。
# ここでは cargoLock.outputHashes を使う。ハッシュのキーは git commit SHA に
# 解決される（1 リポジトリにつき代表クレート 1 件で足りる）ので、OpenLogi 自身
# のバージョンバンプでは無効化されず、gpui などの rev を上げたときだけ更新する。
# =============================================================================
{
  lib,
  rustPlatform,
  fetchgit,
  src,
  pkg-config,
  makeWrapper,
  fontconfig,
  freetype,
  libxkbcommon,
  wayland,
  vulkan-loader,
  libxcb,
}:

let
  # ワークスペース共通バージョン。手で二重管理すると src 更新時にずれるため
  # Cargo.toml の [workspace.package] から抽出する（全クレートが
  # version.workspace = true でこの値を参照している）。抽出できなければ
  # 黙って別の値にフォールバックせず失敗させる。
  cargoToml = builtins.readFile "${src}/Cargo.toml";
  afterHeader = lib.splitString "[workspace.package]" cargoToml;
  versionLine =
    if builtins.length afterHeader < 2 then
      throw "openlogi: Cargo.toml に [workspace.package] セクションが無い"
    else
      lib.findFirst (l: builtins.match "version = \"[^\"]+\"" l != null) null (
        lib.splitString "\n" (builtins.elemAt afterHeader 1)
      );
  version =
    if versionLine == null then
      throw "openlogi: [workspace.package] の version 行を抽出できなかった"
    else
      builtins.head (builtins.match "version = \"([^\"]+)\"" versionLine);

  # GPUI は libwayland-client / libvulkan をリンクせず実行時に dlopen する。
  # NixOS の既定の検索パスには無いため、ラッパーで LD_LIBRARY_PATH を与える。
  # （libxkbcommon 等は RUNPATH 経由で解決されるので列挙しない）
  runtimeLibs = lib.makeLibraryPath [
    wayland
    vulkan-loader
  ];

  # gpui-component のチェックアウト。openlogi-gui の build.rs が upstream の
  # テーマ JSON を OUT_DIR へ取り込むために参照する。テーマはリポジトリルートの
  # themes/ にありクレートのサブディレクトリの外なので、cargoLock 方式の vendor
  # （クレート単位のコピー）には含まれない。build.rs の既定動作は cargo metadata
  # でクレートの位置を探して themes/ へ登るというもので、この配置では失敗するため
  # OPENLOGI_THEMES_DIR で直接指す。hash は下の outputHashes と共有し、rev は
  # Cargo.lock 側と一致している必要がある（ずれれば hash 不一致でビルドが落ちる）。
  gpuiComponentRev = "031555662e99a1b5a549990b47f246d475b8288a";
  gpuiComponentHash = "sha256-yOXdgxQgfvGN2/+OdDnl1pYti0DoGFvS3Tyqvj3Bkng=";
  gpuiComponentSrc = fetchgit {
    url = "https://github.com/longbridge/gpui-component";
    rev = gpuiComponentRev;
    hash = gpuiComponentHash;
  };
in
rustPlatform.buildRustPackage {
  pname = "openlogi";
  inherit version src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    # gpui とその周辺は git 依存。値は nix-prefetch-git で取得したもの。
    outputHashes = {
      "gpui-0.2.2" = "sha256-Av+unZNI39dEb+zwSIU+SkEjqagHWrc7W8KehEgQ4H8=";
      "gpui-component-0.5.2" = gpuiComponentHash;
      "gpui-updater-0.0.5" = "sha256-H2IW7nDD1q/Zbt7ZSft6VTMv5UpjiCg2FIQSoML/CMc=";
      "zed-font-kit-0.14.1-zed" = "sha256-KXygi0olNQi5yM8eaJVykNDtbPMDjT+cWPBF8UrtXR4=";
      "zed-reqwest-0.12.15-zed" = "sha256-p4SiUrOrbTlk/3bBrzN/mq/t+1Gzy2ot4nso6w6S+F8=";
      "zed-scap-0.0.8-zed" = "sha256-BihiQHlal/eRsktyf0GI3aSWsUCW7WcICMsC2Xvb7kw=";
      "zed-xim-0.4.0-zed" = "sha256-pRT4Sz1JU9ros47/7pmIW9kosWOGMOItcnNd+VrvnpE=";
    };
  };

  postPatch = ''
    # gpui-component の IconName proc-macro は自クレートからの相対で
    # `../assets/assets/icons` を読み、upstream リポジトリのワークスペース配置を
    # 前提にしている。vendor ツリーはクレートを平坦に並べるためその兄弟
    # ディレクトリが無く、gpui-component-assets へのリンクで復元する。
    ln -sfn "$cargoDepsCopy"/gpui-component-assets-* "$cargoDepsCopy/assets"
  '';

  env.OPENLOGI_THEMES_DIR = "${gpuiComponentSrc}/themes";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    # `media` (gpui の依存) が bindgen を走らせるので libclang が要る
    rustPlatform.bindgenHook
  ];

  # 対応する *-sys クレートが Cargo.lock にあるものだけを挙げる。
  # openssl / alsa / libudev は依存ツリーに無く（TLS は rustls、evdev と hidraw は
  # pure Rust で直接デバイスノードを開く）、vulkan-loader は dlopen なので
  # ビルド時ではなく下の runtimeLibs 側で供給する。
  buildInputs = [
    fontconfig # GPUI のテキスト描画 (yeslogic-fontconfig-sys)
    freetype # font-kit (freetype-sys)
    libxkbcommon # GPUI のキーボード処理
    wayland # wayland-sys
    libxcb # xcb / x11rb — hook と GPUI の X11 バックエンド
  ];

  # ビルドするのは実際に配布する 3 バイナリだけ。xtask（macOS バンドル・DMG 用）
  # は Linux では使わない。
  cargoBuildFlags = [
    "--package=openlogi"
    "--package=openlogi-agent"
    "--package=openlogi-gui"
  ];

  # テストは Logitech デバイスと D-Bus / uinput を要求するものがあり、
  # サンドボックス内では実行できない。検証はリポジトリ側の Rust CI に委ねる。
  doCheck = false;

  postInstall = ''
    install -Dm644 packaging/linux/desktop/openlogi.desktop \
      "$out/share/applications/openlogi.desktop"
    install -Dm644 design/icon/openlogi.png \
      "$out/share/icons/hicolor/512x512/apps/openlogi.png"

    # udev ルールは modules/openlogi.nix 側の簡約版を使うため、ここでは配置しない
  '';

  postFixup = ''
    wrapProgram "$out/bin/openlogi-gui" \
      --prefix LD_LIBRARY_PATH : "${runtimeLibs}"
  '';

  meta = {
    description = "Local-first alternative to Logitech Options+ for HID++ devices";
    homepage = "https://github.com/tagawa0525/OpenLogi";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "openlogi-gui";
    platforms = lib.platforms.linux;
  };
}
