# =============================================================================
# mise設定（ランタイムバージョンマネージャー）
# =============================================================================
# mise: Ruby, Python, Node.js, Go, Rustなどの複数バージョンを管理
# asdfの後継で、Rust製で高速、互換性も高い
# =============================================================================
{ pkgs, ... }:

{
  # ===========================================================================
  # miseとビルド依存関係
  # ===========================================================================
  home.packages = with pkgs; [
    # mise本体
    mise

    # ─────────────────────────────────────────────────────────────
    # Ruby ビルド依存関係
    # ─────────────────────────────────────────────────────────────
    openssl
    libyaml
    zlib
    readline
    libffi
    gdbm

    # ─────────────────────────────────────────────────────────────
    # Python ビルド依存関係
    # ─────────────────────────────────────────────────────────────
    sqlite
    ncurses
    xz
    bzip2
    tk

    # ─────────────────────────────────────────────────────────────
    # Node.js ビルド依存関係
    # ─────────────────────────────────────────────────────────────
    python3 # Node.jsのビルドに必要

    # ─────────────────────────────────────────────────────────────
    # Rust ビルド依存関係
    # ─────────────────────────────────────────────────────────────
    pkg-config

    # ─────────────────────────────────────────────────────────────
    # 共通ビルドツール
    # ─────────────────────────────────────────────────────────────
    clang # Rustと相性が良い、moldリンカーとの組み合わせ用
    gnumake
    cmake
    autoconf
    automake
    libtool
    git
    curl
    wget
    unzip
  ];

  # ===========================================================================
  # 環境変数（ビルド時に使用）
  # ===========================================================================
  home.sessionVariables = {
    # Clangをデフォルトコンパイラとして使用
    CC = "clang";
    CXX = "clang++";

    # OpenSSL関連（RustやRubyのネイティブ拡張で使用）
    OPENSSL_DIR = "${pkgs.openssl.dev}";
    OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";

    # pkg-config パス（複数ライブラリ対応）
    PKG_CONFIG_PATH = builtins.concatStringsSep ":" [
      "${pkgs.openssl.dev}/lib/pkgconfig"
      "${pkgs.libffi.dev}/lib/pkgconfig"
      "${pkgs.libyaml.dev}/lib/pkgconfig"
      "${pkgs.zlib.dev}/lib/pkgconfig"
      "${pkgs.readline.dev}/lib/pkgconfig"
    ];

    # Ruby ビルド用: ヘッダーファイルのパス
    C_INCLUDE_PATH = builtins.concatStringsSep ":" [
      "${pkgs.openssl.dev}/include"
      "${pkgs.libffi.dev}/include"
      "${pkgs.libyaml.dev}/include"
      "${pkgs.zlib.dev}/include"
      "${pkgs.readline.dev}/include"
    ];

    # Ruby ビルド用: ライブラリファイルのパス
    LIBRARY_PATH = builtins.concatStringsSep ":" [
      "${pkgs.openssl.out}/lib"
      "${pkgs.libffi.out}/lib"
      "${pkgs.libyaml.out}/lib"
      "${pkgs.zlib.out}/lib"
      "${pkgs.readline.out}/lib"
    ];

    # Ruby configure オプション
    RUBY_CONFIGURE_OPTS = builtins.concatStringsSep " " [
      "--with-openssl-dir=${pkgs.openssl.dev}"
      "--with-readline-dir=${pkgs.readline.dev}"
      "--with-libyaml-dir=${pkgs.libyaml.dev}"
    ];
  };
}
