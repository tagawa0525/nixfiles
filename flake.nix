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

    # OpenLogi: Logitech Options+ 代替（fork 運用）
    # nixpkgs 版は macOS 専用。fork の master は自前 flake で Linux 向け
    # パッケージを出しており（upstream #491、#262 で消えた flake の復活）、
    # ハッシュずれは向こうの Nix CI が master push / PR で弾くので、
    # こちらは packages 出力をそのまま使う（定義を二重に持たない）
    openlogi = {
      url = "github:tagawa0525/OpenLogi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mattpocock/skills: Claude Code 向けスキル集。grilling / grill-me を
    # ~/.claude/skills に配備する（対象は modules/home/parts/claude-code.nix の
    # externalSkills）。flake ではないので出所と rev の記録のためだけに input にする
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
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
      openlogi,
      mattpocock-skills,
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
      # OpenLogi パッケージ（fork の flake 出力）
      # ─────────────────────────────────────────────────────────────────────────
      # overlay（各ホストの pkgs.openlogi）と packages 出力の両方がここを参照する。
      # nixpkgs は follows でこちらに揃えてあるので、fork 側の nixpkgs が実体化
      # されることはない。
      #
      # meta.mainProgram は fork 側の "openlogi"（CLI）を採用する。以前の
      # ローカル定義は "openlogi-gui" だったので `nix run .#openlogi` の起動対象が
      # 変わるが、この出力は CI（openlogi-cargo-deps）と単体ビルド用で、
      # GUI の起動は .desktop（Exec=openlogi-gui）が担うため実害はない。
      # 上書きするとまた fork との差分を抱えるので置かない
      openlogiPkg = openlogi.packages.x86_64-linux.openlogi;

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
                # OpenLogi: fork の flake が出す Linux パッケージ（modules/openlogi.nix が参照）
                (_final: _prev: { openlogi = openlogiPkg; })
                # cc-bar の overlay は ./modules/cc-bar.nix に集約済み
              ];
              # Home Manager設定
              home-manager.useGlobalPkgs = true; # システムのnixpkgsを使用
              home-manager.useUserPackages = true; # ユーザーパッケージをシステムに統合
              home-manager.backupFileExtension = "backup"; # 既存ファイルのバックアップ拡張子
              # flakeソースとVS Code ServerモジュールをHome Managerに渡す
              # kikitori の systemd サービス定義（services.kikitori.*）を全ユーザーに公開
              home-manager.sharedModules = [ kikitori.homeManagerModules.default ];
              home-manager.extraSpecialArgs = {
                claudeCodeSource = self; # flakeルートを渡す（Claude Code設定用）
                inherit mattpocock-skills; # 外部スキルの取得元（claude-code.nix の externalSkills）
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

      # CI (openlogi-drift.yml) が fork の master HEAD に対して vendor 取得を
      # 検証するためのエントリポイント。openlogi-cargo-deps は importCargoLock
      # の vendor ディレクトリで、これのビルド = 全依存の取得とハッシュ検証。
      # rust のコンパイルを伴わないため、gpui 等の rev bump によるハッシュずれを
      # 数分で検知できる（コンパイルまで通るかは通常の update フローが担う）
      packages.x86_64-linux = {
        openlogi = openlogiPkg;
        openlogi-cargo-deps = openlogiPkg.cargoDeps;
      };
    };
}
