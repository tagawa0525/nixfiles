# =============================================================================
# mise設定（ランタイムバージョンマネージャー）
# =============================================================================
# mise: Ruby, Python, Node.js, Go, Rustなどの複数バージョンを管理
# asdfの後継で、Rust製で高速、互換性も高い
# =============================================================================
{ pkgs, lib, ... }:

let
  # ===========================================================================
  # ランタイムをソースからビルドする際に必要なCライブラリ
  # ===========================================================================
  # Nixではヘッダが .dev 出力に分かれるため、パッケージを home.packages に
  # 入れるだけではコンパイラから見えない。各パスはこのリストから機械的に
  # 生成し、追加時の設定漏れを防ぐ。
  # （bzip2 がパスに含まれておらず Python の _bz2 が欠落し、
  # 　それを import する Node.js の configure が失敗した実例がある）
  buildLibs = with pkgs; [
    # 共通（Ruby / Python の両方が使用）
    openssl # ssl
    zlib # zlib
    readline # readline
    libffi # ctypes

    # Ruby
    libyaml # psych（YAML）

    # Python標準ライブラリのC拡張
    bzip2 # bz2
    xz # lzma
    sqlite # sqlite3
    ncurses # curses
    gdbm # dbm.gnu
    zstd # compression.zstd
    libuuid # uuid（_uuid拡張）
    tcl # tkinter
    tk # tkinter
    libx11 # tkinter（tk.h が X11/Xlib.h を要求する）
    xorgproto # tkinter（X11の基本ヘッダ）
  ];
in
{
  # ===========================================================================
  # miseとビルド依存関係
  # ===========================================================================
  home.packages =
    with pkgs;
    [
      # mise本体
      mise

      # ─────────────────────────────────────────────────────────────
      # ビルドツール
      # ─────────────────────────────────────────────────────────────
      clang # Rustと相性が良い、moldリンカーとの組み合わせ用
      gnumake
      cmake
      autoconf
      automake
      libtool
      pkg-config
      python3 # Node.jsのビルドに必要
      git
      curl
      wget
      unzip
    ]
    ++ buildLibs;

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

    # buildLibs から生成（configure が pkg-config / ヘッダ / リンクで参照）
    PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildLibs;

    # 一般的なコンパイラ・ビルドツール向け（Rustのccクレート等が参照）
    C_INCLUDE_PATH = lib.makeSearchPathOutput "dev" "include" buildLibs;
    LIBRARY_PATH = lib.makeLibraryPath buildLibs;

    # autoconf の configure 向け。pkg-config を持たないライブラリ
    # （bzip2, xz, gdbm, tk 等）は configure がヘッダを直接探すが、
    # C_INCLUDE_PATH ではmise（python-build）経由のビルドに効かないため、
    # CPPFLAGS / LDFLAGS で明示的に渡す必要がある。
    # RUNPATHも同時に埋め、ビルドしたバイナリの実行時解決を保証する。
    CPPFLAGS = lib.concatMapStringsSep " " (p: "-I${lib.getDev p}/include") buildLibs;
    LDFLAGS = lib.concatMapStringsSep " " (
      p: "-L${lib.getLib p}/lib -Wl,-rpath,${lib.getLib p}/lib"
    ) buildLibs;

    # Ruby configure オプション
    RUBY_CONFIGURE_OPTS = builtins.concatStringsSep " " [
      "--with-openssl-dir=${pkgs.openssl.dev}"
      "--with-readline-dir=${pkgs.readline.dev}"
      "--with-libyaml-dir=${pkgs.libyaml.dev}"
    ];
  };
}
