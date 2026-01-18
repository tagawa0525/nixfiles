{ lib
, stdenv
, fetchurl
, makeWrapper
, autoPatchelfHook
, wrapGAppsHook
, alsa-lib
, at-spi2-atk
, cairo
, cups
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, libdrm
, libnotify
, libpulseaudio
, libsecret
, libuuid
, libxkbcommon
, mesa
, nspr
, nss
, pango
, systemd
, xorg
, libkrb5
}:

let
  # VSCode最新版のメタデータを取得するスクリプト
  # Microsoft公式APIから最新のstableバージョン情報を取得
  inherit (stdenv.hostPlatform) system;
  plat = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    armv7l-linux = "linux-armhf";
  }.${system};

  # 最新版の情報（GitHub Actionsで自動更新される）
  version = "1.96.4";
  sha256 = "0000000000000000000000000000000000000000000000000000";

in
stdenv.mkDerivation rec {
  pname = "vscode";
  inherit version;

  src = fetchurl {
    name = "vscode-${version}.tar.gz";
    url = "https://update.code.visualstudio.com/${version}/${plat}/stable";
    inherit sha256;
  };

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
    wrapGAppsHook
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libpulseaudio
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libxkbfile
    xorg.libxshmfence
    libkrb5
  ];

  runtimeDependencies = [
    (lib.getLib systemd)
  ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/vscode $out/bin
    cp -r ./* $out/lib/vscode
    ln -s $out/lib/vscode/bin/code $out/bin/code

    runHook postInstall
  '';

  meta = with lib; {
    description = "Visual Studio Code - latest version";
    homepage = "https://code.visualstudio.com/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" "armv7l-linux" ];
    mainProgram = "code";
  };
}
