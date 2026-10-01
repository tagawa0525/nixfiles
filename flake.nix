# =============================================================================
# NixOS Flake設定
# =============================================================================
# Flakeはnixpkgsの新しいパッケージ管理方式で、再現性のある環境を提供します。
# flake.lockにより依存関係のバージョンが固定され、どの環境でも同じ結果になります。
#
# 使い方:
#   sudo nixos-rebuild switch --flake .#<hostname>
#   例: sudo nixos-rebuild switch --flake .#t14g4
# =============================================================================
{
  description = "NixOS configuration";

  # ===========================================================================
  # 入力（依存パッケージ）
  # ===========================================================================
  inputs = {
    # メインのパッケージリポジトリ（unstableで最新パッケージを使用）
    # nixpkgs-unstable はパッケージビルドテストのみ通過。nixos-unstable は
    # NixOS 統合テストも通過するが、リリース境界では数日〜2週間遅れることがある。
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Home Manager: ユーザー設定（ドットファイル）を宣言的に管理
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs"; # nixpkgsのバージョンを統一
    };

    # Lanzaboote: NixOSでSecure Bootを有効にするためのツール
    # 自己署名したカーネル/initrdで起動可能
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      # Rustバージョンの非互換を避けるためnixpkgsをフォローしない
    };

    # 個人NUR: VSCode最新版
    nur-vscode-latest = {
      url = "github:tagawa0525/nur-vscode-latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VSCode拡張機能（マーケットプレイス + Open VSX）
    # vadimcn.vscode-lldb は nixpkgs 本家の vscode-extensions 経由で供給する
    # （上流 default.nix の supportedVersion assertion が 1.12.1 固定のため、
    #   nix-vscode-extensions 経由だと新バージョンが出るたびに壊れる）
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI Coding Agents: claude-code, opencodeなど
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VS Code Server for NixOS: リモートSSH接続時のNode.jsバイナリ自動パッチ
    # 上流 #101 (flake-parts 化) で評価対象が Linux のみになり、以前あった
    # x86_64-darwin の評価警告は解消したため通常の flake として利用する
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";

    # qmpo: directory:// URIハンドラ
    qmpo = {
      url = "github:tagawa0525/qmpo";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cc-bar: Claude Code Context Window Monitor（COSMICパネルアプレット）
    cc-bar = {
      url = "github:tagawa0525/cc-bar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # kikitori: 完全ローカル・リアルタイム表示の日本語音声入力（voxtype 後継）
    kikitori = {
      url = "github:tagawa0525/kikitori";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenLogi: Logitech Options+ 代替
    # nixpkgs 版は macOS 専用。upstream の flake はソースからビルドするため
    # GPUI を含む Rust のコンパイルが更新のたびに走る。個人 NUR が upstream の
    # Release にあるビルド済みパッケージを包み直したものを使い、コンパイルを
    # なくす（毎日 minisign 検証つきで最新リリースに追従。GPUI の実行時ライブラリ
    # も全バイナリの RUNPATH に入っている）
    nur-openlogi-latest = {
      url = "github:tagawa0525/nur-openlogi-latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mattpocock/skills: Claude Code 向けスキル集。grilling / grill-me を
    # ~/.claude/skills にデプロイする（対象は modules/home/parts/claude-code.nix の
    # externalSkills）。flake ではないので出所と rev の記録のためだけに input にする
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # lsp-det: 言語サーバーの状態を示す透過プロキシ（自作）。packages.default を
    # Claude Code の LSP の経路に挟んでドッグフーディングする（claude-code.nix）。
    # 更新は nix flake update lsp-det → rebuild
    lsp-det = {
      url = "github:tagawa0525/lsp-det";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nucrawler: 原子力（軽水炉）ニュースの巡回・和訳・要約・推薦（自作）。
    # home-manager モジュール（services.nucrawler）を全ユーザーに公開し、
    # 有効化は常時通電の r995 だけで行う（hosts/r995/default.nix）
    nucrawler = {
      url = "github:tagawa0525/nucrawler";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ===========================================================================
  # 出力（システム設定）
  # ===========================================================================
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      lanzaboote,
      nix-vscode-extensions,
      nur-vscode-latest,
      llm-agents,
      nixos-vscode-server,
      qmpo,
      cc-bar,
      kikitori,
      nur-openlogi-latest,
      mattpocock-skills,
      lsp-det,
      nucrawler,
      ...
    }:
    let
      # ─────────────────────────────────────────────────────────────────────────
      # ホスト一覧（hosts/ 配下のディレクトリ名を自動検出）
      # ─────────────────────────────────────────────────────────────────────────
      # ホスト追加 = hosts/<hostName>/ を作成、削除 = ディレクトリごと削除。
      # 手順の詳細は hosts/TEMPLATE.md を参照。
      hostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      # ─────────────────────────────────────────────────────────────────────────
      # mkHost: ホスト設定を生成するヘルパー関数
      # ─────────────────────────────────────────────────────────────────────────
      # 引数: ホスト名（hosts/<hostName>/配下に設定ファイルが必要）
      # networking.hostName はディレクトリ名から自動設定される（mkDefault のため
      # ホスト側で上書きも可能）。
      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit self cc-bar; }; # flakeルートと cc-bar input を modules に渡す
          modules = [
            ./hosts/${hostName} # ホスト固有設定（ブート、ハードウェア等）
            { networking.hostName = nixpkgs.lib.mkDefault hostName; }
            ./modules/profiles/base.nix # 全ホスト共通の最小ベース設定
            ./modules/cc-bar.nix # cc-bar 統合（無効化するにはこの行をコメントアウト）
            ./modules/handlr-regex-fix.nix # handlr-regex のテスト期待値パッチ（撤去手順は同ファイル冒頭）
            ./modules/gcc16-compat.nix # zat / ltrace の gcc 16 対処（撤去手順は同ファイル冒頭）
            lanzaboote.nixosModules.lanzaboote # Secure Bootサポート
            home-manager.nixosModules.home-manager
            {
              # オーバーレイを追加
              nixpkgs.overlays = [
                # 個人NUR: VSCode最新版（本体のみ）
                (final: prev: {
                  nur-vscode-latest = nur-vscode-latest.packages.${prev.stdenv.hostPlatform.system};
                })
                # VSCode拡張機能（nix-vscode-extensions）
                nix-vscode-extensions.overlays.default
                # AI Coding Agents
                (final: prev: {
                  llm-agents = llm-agents.packages.${prev.stdenv.hostPlatform.system};
                })
                # qmpo: directory:// URIハンドラ
                qmpo.overlays.default
                # kikitori: ローカル音声入力（voice-input.nix のショートカットが参照）
                (final: prev: {
                  kikitori = kikitori.packages.${prev.stdenv.hostPlatform.system}.kikitori;
                })
                # OpenLogi: 個人 NUR のビルド済みパッケージ（modules/openlogi.nix が参照）
                (final: prev: {
                  openlogi = nur-openlogi-latest.packages.${prev.stdenv.hostPlatform.system}.openlogi;
                })
                # cc-bar の overlay は ./modules/cc-bar.nix に集約済み
              ];
              # Home Manager設定
              home-manager.useGlobalPkgs = true; # システムのnixpkgsを使用
              home-manager.useUserPackages = true; # ユーザーパッケージをシステムに統合
              home-manager.backupFileExtension = "backup"; # 既存ファイルのバックアップ拡張子
              # flakeソースとVS Code ServerモジュールをHome Managerに渡す
              # kikitori の systemd サービス定義（services.kikitori.*）を全ユーザーに公開
              # nucrawler の timer と Web UI の定義（services.nucrawler.*）も同様
              home-manager.sharedModules = [
                kikitori.homeManagerModules.default
                nucrawler.homeManagerModules.default
              ];
              home-manager.extraSpecialArgs = {
                claudeCodeSource = self; # flakeルートを渡す（Claude Code設定用）
                inherit mattpocock-skills; # 外部スキルの取得元（claude-code.nix の externalSkills）
                inherit lsp-det; # ドッグフーディングの lsp-det（claude-code.nix）
                vscode-server = nixos-vscode-server; # VS Code Server自動パッチモジュール
              };
              # 各ユーザーの home-manager.users.<name> は modules/users/<name>.nix が
              # 定義する（ホストが import したユーザーだけがそのホストに住む）
            }
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;

      packages.x86_64-linux = {
        # Claude Code の PreToolUse hook（modules/home/parts/claude-code.nix が home に配置する）。
        # nix build .#claude-hooks で単体ビルドし、テストから CLAUDE_HOOKS_BIN で参照する
        claude-hooks =
          nixpkgs.legacyPackages.x86_64-linux.callPackage ./modules/home/parts/claude-hooks/package.nix
            { };
      };
    };
}
