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
      url = "github:nix-community/lanzaboote/v0.4.2";
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
    nixos-vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
  };

  # ===========================================================================
  # 出力（システム設定）
  # ===========================================================================
  outputs =
    { self
    , nixpkgs
    , home-manager
    , lanzaboote
    , nix-vscode-extensions
    , nur-vscode-latest
    , llm-agents
    , nixos-vscode-server
    , qmpo
    , cc-bar
    , ...
    }:
    let
      # ─────────────────────────────────────────────────────────────────────────
      # ホスト一覧
      # ─────────────────────────────────────────────────────────────────────────
      hostList = [
        "t14g4" # t14g4: ノートPC (ThinkPad T14 4th Gen)
        "x1ng1" # x1ng1: ノートPC (ThinkPad X1 Nano 1st Gen)
        "r995" # r995: デスクトップ (Ryzen 9950X + AMD GPU)
      ];

      # ─────────────────────────────────────────────────────────────────────────
      # mkHost: ホスト設定を生成するヘルパー関数
      # ─────────────────────────────────────────────────────────────────────────
      # 引数: ホスト名（hosts/<hostName>/配下に設定ファイルが必要）
      # 新しいホストを追加する場合:
      #   1. hostList に追加
      #   2. SSH公開鍵を該当ユーザーの個人設定に配置
      #      （例：modules/home/users/<user>/keys/<hostName>.pub）
      #   3. hosts/<hostName>/default.nix と hardware-configuration.nix を作成
      # ─────────────────────────────────────────────────────────────────────────
      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit self cc-bar; }; # flakeルートと cc-bar input を modules に渡す
          modules = [
            ./hosts/${hostName} # ホスト固有設定（ブート、ホスト名等）
            ./modules/profiles/base.nix # 全ホスト共通の最小ベース設定
            # ./modules/cc-bar.nix # cc-bar 統合（有効化するにはこの行のコメントを外す）
            lanzaboote.nixosModules.lanzaboote # Secure Bootサポート
            home-manager.nixosModules.home-manager
            {
              # オーバーレイを追加
              nixpkgs.overlays = [
                # 個人NUR: VSCode最新版（本体のみ）
                (final: prev: {
                  nur-vscode-latest = nur-vscode-latest.packages.${prev.stdenv.hostPlatform.system};
                })
                # jedi-language-server 0.46.0 は jedi<0.20 を要求するが、nixpkgs 側の
                # jedi が 0.20.0 に更新されたため pythonRuntimeDepsCheckHook で
                # ビルドが失敗する。実際の動作には支障がないため、依存バージョン制約を
                # 緩めて nixpkgs 上流の修正までの繋ぎとする。
                # 解消したら overlay ごと削除する。
                #
                # `python313` を override することで、そこから派生する全エイリアス
                # (python3, python3Packages, python313Packages) に修正が反映される。
                (final: prev: {
                  python313 = prev.python313.override {
                    packageOverrides = pyfinal: pyprev: {
                      jedi-language-server = pyprev.jedi-language-server.overrideAttrs (oldAttrs: {
                        pythonRelaxDeps = (oldAttrs.pythonRelaxDeps or [ ]) ++ [ "jedi" ];
                      });
                    };
                  };
                })
                # VSCode拡張機能（nix-vscode-extensions）
                nix-vscode-extensions.overlays.default
                # AI Coding Agents
                (final: prev: {
                  llm-agents = llm-agents.packages.${prev.stdenv.hostPlatform.system};
                })
                # qmpo: directory:// URIハンドラ
                qmpo.overlays.default
                # cc-bar の overlay は ./modules/cc-bar.nix に集約済み
              ];
              # Home Manager設定
              home-manager.useGlobalPkgs = true; # システムのnixpkgsを使用
              home-manager.useUserPackages = true; # ユーザーパッケージをシステムに統合
              home-manager.backupFileExtension = "backup"; # 既存ファイルのバックアップ拡張子
              # flakeソースとVS Code ServerモジュールをHome Managerに渡す
              home-manager.extraSpecialArgs = {
                claudeCodeSource = self; # flakeルートを渡す（Claude Code設定用）
                vscode-server = nixos-vscode-server; # VS Code Server自動パッチモジュール
              };
              home-manager.users.tagawa = import ./modules/home/users/tagawa/default.nix;
            }
          ];
        };
    in
    {
      nixosConfigurations = builtins.listToAttrs (map
        (hostName: {
          name = hostName;
          value = mkHost hostName;
        })
        hostList);
    };
}
