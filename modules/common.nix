# =============================================================================
# 全ホスト共通のシステム設定
# =============================================================================
# このファイルはxc8(ノートPC)とr995(デスクトップ)で共有される設定を定義します。
# ホスト固有の設定は hosts/<hostname>/default.nix に記述してください。
# =============================================================================
#
# TODO: Btrfs マウントオプション最適化
#   hosts/*/hardware-configuration.nix の fileSystems."/" に以下を追加:
#   options = [ "subvol=@root" "compress=zstd" "noatime" ];
#   - compress=zstd: 透過的圧縮でディスク使用量削減
#   - noatime: アクセス時刻の更新を無効化（SSD寿命・パフォーマンス改善）
#
# =============================================================================
{ pkgs, lib, ... }:

{
  # ===========================================================================
  # Nix設定
  # ===========================================================================
  # flakesとnix commandを有効化（従来のnix-buildに代わる新しいCLI）
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # wheelグループのユーザーを信頼されたユーザーに設定
    # これにより、ユーザーレベルの設定（extra-trusted-public-keysなど）が有効になる
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
  # 自動ガベージコレクション: 30日以上古い世代を週次で削除
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  # プロプライエタリソフトウェア（Chrome、VSCode等）のインストールを許可
  nixpkgs.config.allowUnfree = true;

  # ===========================================================================
  # ハードウェア
  # ===========================================================================
  # AMD/Intel CPUのマイクロコード更新、WiFi/Bluetoothファームウェア等を有効化
  hardware.enableRedistributableFirmware = true;

  # ===========================================================================
  # ネットワーク
  # ===========================================================================
  # NetworkManagerでWi-Fi/有線を管理（GUIからも設定可能）
  networking.networkmanager.enable = true;
  # DNSサーバーを明示指定（プライマリ: Cloudflare、フォールバック: Google）
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  # ===========================================================================
  # タイムゾーンとロケール
  # ===========================================================================
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.supportedLocales = [
    "ja_JP.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8" # 英語ロケールも必要（一部アプリが要求）
  ];

  # ===========================================================================
  # フォント
  # ===========================================================================
  # 日本語表示に必要なフォントと開発用フォントをインストール
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans # Google Noto日本語フォント
    noto-fonts-color-emoji # 絵文字フォント
    nerd-fonts.jetbrains-mono # 開発用フォント（アイコン付き）
    font-awesome # アイコンフォント（ステータスバー等で使用）
  ];
  # システム全体のデフォルトフォントを日本語対応に設定
  fonts.fontconfig = {
    defaultFonts = {
      sansSerif = [
        "Noto Sans CJK JP"
        "Noto Sans"
      ];
      monospace = [
        "Noto Sans Mono CJK JP"
        "Noto Sans Mono"
      ];
    };
  };

  # ===========================================================================
  # 日本語入力 (fcitx5 + Mozc)
  # ===========================================================================
  # fcitx5: 入力メソッドフレームワーク
  # Mozc: Google日本語入力のオープンソース版
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc # 日本語変換エンジン
      fcitx5-gtk # GTKアプリとの統合
    ];
  };

  # ===========================================================================
  # 環境変数
  # ===========================================================================
  environment.sessionVariables = {
    # Electron/ChromiumアプリをWaylandネイティブで動作させる
    NIXOS_OZONE_WL = "1";
  };

  # ===========================================================================
  # デスクトップ環境 (COSMIC DE)
  # ===========================================================================
  # System76が開発中のRust製デスクトップ環境
  # Waylandネイティブでタイル型ウィンドウ管理をサポート
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # ===========================================================================
  # コンテナ (Podman)
  # ===========================================================================
  # DockerのRootless代替。デーモン不要でセキュリティが高い
  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # dockerコマンドをpodmanにエイリアス
    defaultNetwork.settings.dns_enabled = true; # コンテナ間DNS解決
  };
  # Rootlessコンテナに必要なユーザー名前空間を許可
  security.unprivilegedUsernsClone = true;

  # ===========================================================================
  # 仮想化 (libvirt/KVM)
  # ===========================================================================
  # ハードウェア仮想化によるVM実行環境
  # Windows VM、開発環境の分離などに使用
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true; # VM管理用GUI
  # NixOSではFHS準拠の/usr/binが存在しないため、このサービスを明示的に上書きする
  # ExecStartはリスト型なので空文字で既存エントリをクリアしてから置換する
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart =
    let
      script = pkgs.writeShellScript "virt-secret-init-encryption" ''
        umask 0077
        dd if=/dev/random status=none bs=32 count=1 \
          | ${pkgs.systemd}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key
      '';
    in
    lib.mkForce [ "" "${script}" ];

  # ===========================================================================
  # ユーザーアカウント
  # ===========================================================================
  users.users.tagawa = {
    isNormalUser = true;
    # Rootlessコンテナ用のサブUID/GID範囲を割り当て
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
    # wheel: sudo権限, podman: コンテナ操作, libvirtd: VM操作
    extraGroups = [
      "wheel"
      "podman"
      "libvirtd"
    ];
    # mkpasswd -m sha-512 で生成したハッシュ
    hashedPassword = "$6$g8T1ZyjV8uoBKzcp$HPjF9mnYkkpEyY3NXeK1HXv.Y3vcUSN4bHkzktlzuSi9SHxBYcNbbhtfwYHMSw5gQ2spy8fF9MORT.oUOUboA.";
    shell = pkgs.bash; # デフォルトはbash（VSCode-Server等の互換性のため）
  };

  # ===========================================================================
  # プログラム
  # ===========================================================================
  programs.firefox.enable = true;
  programs.fish.enable = true; # tmux内で使用

  # ===========================================================================
  # nix-ld（動的リンカー互換レイヤー）
  # ===========================================================================
  # FHS非準拠のNixOSで、/lib64/ld-linux-x86-64.so.2を期待する
  # 外部バイナリ（VS Code Server等）を動作させるために必要
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # VS Code Server、その他の外部バイナリが必要とする基本ライブラリ
      stdenv.cc.cc.lib # libstdc++.so
      zlib # libz.so（圧縮）
      openssl # libssl.so, libcrypto.so
      curl # libcurl.so
      icu # Unicode処理
      libsecret # シークレット管理
      libunwind # スタックトレース
      libuuid # UUID生成
      krb5 # Kerberos認証
    ];
  };

  # ===========================================================================
  # システムパッケージ
  # ===========================================================================
  environment.systemPackages = with pkgs; [
    # ─────────────────────────────────────────────────────────────
    # ブラウザ
    # ─────────────────────────────────────────────────────────────
    google-chrome # Chromiumベース。開発者ツールが充実

    # ─────────────────────────────────────────────────────────────
    # エディタ・ターミナル
    # ─────────────────────────────────────────────────────────────
    neovim # Vimの後継。Luaで拡張可能
    neovide # Neovim用GUI。アニメーションやIME対応が優秀
    alacritty # Rust製GPU加速ターミナル。設定はYAML

    # ─────────────────────────────────────────────────────────────
    # 言語・ランタイム
    # ─────────────────────────────────────────────────────────────
    clang # C/C++コンパイラ。GCCより高速でエラーメッセージが分かりやすい
    rustup # Rustツールチェーン管理。rustc, cargo, rustfmt等を管理
    ruby # Ruby言語の最新安定版
    python3 # Python 3の最新安定版
    uv # Rust製Python環境管理。pip/venvより10-100倍高速
    nil # Nix言語サーバー。エディタでの補完・診断に使用
    nixd # Nix言語サーバー（VS Code Nix拡張機能が使用）

    # ─────────────────────────────────────────────────────────────
    # ビルドツール
    # ─────────────────────────────────────────────────────────────
    gnumake # Makeビルドシステム。多くのプロジェクトで使用
    cmake # CMakeビルドシステム。クロスプラットフォーム対応

    # ─────────────────────────────────────────────────────────────
    # バージョン管理
    # ─────────────────────────────────────────────────────────────
    git # 分散バージョン管理システム
    gh # GitHub CLI。PR作成、Issue管理がターミナルから可能
    lazygit # Git用TUI。ステージング、コミット、ブランチ操作が直感的
    gitui # ターミナルベースのGit UI
    delta # git diffを見やすく表示。シンタックスハイライト対応

    # ─────────────────────────────────────────────────────────────
    # CLIユーティリティ - 検索・ナビゲーション
    # ─────────────────────────────────────────────────────────────
    ripgrep # Rust製grep。.gitignoreを尊重し高速検索
    fd # Rust製find。シンプルな構文で高速検索
    fzf # ファジーファインダー。履歴検索やファイル選択に
    zoxide # cdの学習型代替。z <部分一致>でジャンプ

    # ─────────────────────────────────────────────────────────────
    # CLIユーティリティ - ネットワーク
    # ─────────────────────────────────────────────────────────────
    curl # HTTP/HTTPSリクエスト。APIテストやファイルダウンロード
    wget # ファイルダウンロード。再帰的ダウンロード対応
    socat # 多機能ソケットツール。netcatの上位互換
    nmap # ネットワークスキャン。ポート開放確認に
    dig # DNS問い合わせ。名前解決のデバッグに
    tcpdump # パケットキャプチャ。ネットワーク問題の診断に

    # ─────────────────────────────────────────────────────────────
    # CLIユーティリティ - ファイル・テキスト
    # ─────────────────────────────────────────────────────────────
    eza # Rust製ls。アイコン、Git状態、ツリー表示対応
    bat # Rust製cat。シンタックスハイライトと行番号付き
    tree # ディレクトリ構造をツリー表示。Claude Codeでよく使用
    jq # JSONをコマンドラインで整形・フィルタリング
    yq-go # YAMLをコマンドラインで整形・フィルタリング
    file # ファイルタイプの判定
    vim-full # xxdコマンドを含む完全版vim。バイナリエディタに使用
    gnused # GNU sed。スクリプトやClaude Codeで使用
    gnugrep # GNU grep。パターン検索（ripgrepの補完）
    diffutils # diff, cmp, patch。ファイル比較・差分適用
    gnutar # GNU tar。アーカイブ作成・展開
    gzip # gzip圧縮・解凍
    bzip2 # bzip2圧縮・解凍
    xz # xz圧縮・解凍
    unzip # ZIPアーカイブ展開
    zip # ZIPアーカイブ作成
    bc # 任意精度計算機。シェルでの浮動小数点計算やスクリプト内の数値処理
    tmux # ターミナル多重化。セッション保持やペイン分割
    entr # ファイル変更をトリガーにコマンド実行。TDDサイクルの自動化に
    watchexec # Rust製ファイル監視。entrの高機能版

    # ─────────────────────────────────────────────────────────────
    # デバッグ・分析
    # ─────────────────────────────────────────────────────────────
    strace # プロセスのシステムコールをトレース。デバッグに必須
    ltrace # ライブラリ関数呼び出しをトレース
    lsof # 開いているファイルとプロセスの対応を表示。ポート使用調査に
    psmisc # pstree, killall等。プロセスのツリー構造表示に
    inotify-tools # inotifywait。ファイル変更の監視・デバッグに
    tokei # 言語別コード行数カウント。プロジェクト規模把握に
    hyperfine # コマンドのベンチマーク。複数コマンドの比較が簡単
    dust # Rust製du。ディスク使用量を視覚的に表示
    sqlite # SQLiteデータベースCLI。ローカルDB操作やデータ分析に使用

    # ─────────────────────────────────────────────────────────────
    # システム監視
    # ─────────────────────────────────────────────────────────────
    htop # プロセス一覧とリソース使用状況をリアルタイム表示
    btop # htopの高機能版。CPU/メモリ/ネットワークをグラフ表示
    cosmic-ext-applet-minimon # COSMICパネル用システムモニター
    cc-bar # COSMICパネル用Claude Codeコンテキストモニター

    # ─────────────────────────────────────────────────────────────
    # GUIツール - 開発
    # ─────────────────────────────────────────────────────────────
    podman-desktop # コンテナ管理GUI。Docker Desktopの代替
    meld # ファイル/ディレクトリの差分比較・マージ
    dbeaver-bin # 多数のDBに対応したGUIクライアント

    # ─────────────────────────────────────────────────────────────
    # システムユーティリティ
    # ─────────────────────────────────────────────────────────────
    wl-clipboard # Wayland用クリップボード操作（wl-copy, wl-paste）
    waypipe # WaylandアプリをSSH経由で転送。リモートGUIアプリの実行に使用
    sbctl # Secure Boot鍵管理。自己署名鍵の作成・登録
  ];

  # ===========================================================================
  # GNOME Keyring
  # ===========================================================================
  # SSH鍵、GPG鍵、アプリのパスワードを安全に保管
  # ログイン時に自動でアンロックされる
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;

  # ===========================================================================
  # システムログ (journald)
  # ===========================================================================
  # ログサイズを500MBに制限（Btrfsサブボリュームが同一パーティションを共有するため）
  services.journald.extraConfig = "SystemMaxUse=500M";

  # ===========================================================================
  # SSH
  # ===========================================================================
  # リモートからのSSH接続を許可（公開鍵認証のみ）
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no"; # rootログイン禁止
      PasswordAuthentication = false; # パスワード認証禁止（鍵認証のみ）
    };
    ports = [ 22 ];
  };

  # ===========================================================================
  # Tailscale (VPN)
  # ===========================================================================
  # WireGuardベースのメッシュVPN。NAT越えが簡単で、
  # 自宅PCへのリモートアクセスやデバイス間通信に使用
  services.tailscale.enable = true;

  # ===========================================================================
  # キーリマップ (keyd)
  # ===========================================================================
  # Wayland/X11/TTY全てで動作するキーリマッパー
  # CapsLockを「単独押し=Esc」「長押し/組み合わせ=Ctrl」に変更
  # Vim使用時に非常に便利
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ]; # 全キーボードに適用
      settings.main = {
        capslock = "overload(control, esc)";
      };
    };
  };

  # ===========================================================================
  # ファイアウォール
  # ===========================================================================
  # SSH(22)のみ許可。他のポートは必要に応じて追加
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ===========================================================================
  # XDGユーザーディレクトリ
  # ===========================================================================
  # ホームディレクトリの標準フォルダ構成を定義
  environment.etc."xdg/user-dirs.defaults".text = ''
    DESKTOP=Desktop
    DOWNLOAD=Downloads
    TEMPLATES=Templates
    PUBLICSHARE=Public
    DOCUMENTS=Documents
    MUSIC=Music
    PICTURES=Pictures
    VIDEOS=Videos
  '';
}
