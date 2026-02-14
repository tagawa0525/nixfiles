# =============================================================================
# NixOS Flake設定
# =============================================================================
# Flakeはnixpkgsの新しいパッケージ管理方式で、再現性のある環境を提供します。
# flake.lockにより依存関係のバージョンが固定され、どの環境でも同じ結果になります。
#
# 使い方:
#   sudo nixos-rebuild switch --flake .#<hostname>
#   例: sudo nixos-rebuild switch --flake .#xc8
# =============================================================================
{
  description = "NixOS configuration";

  # ===========================================================================
  # 入力（依存パッケージ）
  # ===========================================================================
  inputs = {
    # メインのパッケージリポジトリ（unstableで最新パッケージを使用）
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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

    # sops-nix: シークレット管理（age暗号化）
    sops-nix = {
      url = "github:Mic92/sops-nix";
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
    , sops-nix
    , cc-bar
    , ...
    }:
    let
      # ─────────────────────────────────────────────────────────────────────────
      # mkHost: ホスト設定を生成するヘルパー関数
      # ─────────────────────────────────────────────────────────────────────────
      # 引数: ホスト名（hosts/<hostName>/配下に設定ファイルが必要）
      # 新しいホストを追加する場合:
      #   1. hosts/<hostName>/default.nix と hardware-configuration.nix を作成
      #   2. hosts/<hostName>/niri-output.nix を作成
      #   3. nixosConfigurations に `<hostName> = mkHost "<hostName>";` を追加
      # ─────────────────────────────────────────────────────────────────────────
      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/${hostName} # ホスト固有設定（ブート、ホスト名等）
            ./modules/common.nix # 共通システム設定
            lanzaboote.nixosModules.lanzaboote # Secure Bootサポート
            sops-nix.nixosModules.sops # シークレット管理
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
                # cc-bar: Claude Code Context Window Monitor
                cc-bar.overlays.default
              ];
              # Home Manager設定
              home-manager.useGlobalPkgs = true; # システムのnixpkgsを使用
              home-manager.useUserPackages = true; # ユーザーパッケージをシステムに統合
              home-manager.backupFileExtension = "backup"; # 既存ファイルのバックアップ拡張子
              # ホスト固有のディスプレイ設定とflakeソースをHome Managerに渡す
              home-manager.extraSpecialArgs = (import ./hosts/${hostName}/niri-output.nix) // {
                claudeCodeSource = self; # flakeルートを渡す（Claude Code設定用）
                vscode-server = nixos-vscode-server; # VS Code Server自動パッチモジュール
              };
              home-manager.users.tagawa = import ./modules/home/tagawa.nix;
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        xc8 = mkHost "xc8"; # ノートPC (ThinkPad X1 Carbon 8th Gen)
        r995 = mkHost "r995"; # デスクトップ (Ryzen 9950X + AMD GPU)
      };
    };
}
