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
      inputs.nixpkgs.follows = "nixpkgs";  # nixpkgsのバージョンを統一
    };

    # Lanzaboote: NixOSでSecure Bootを有効にするためのツール
    # 自己署名したカーネル/initrdで起動可能
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      # Rustバージョンの非互換を避けるためnixpkgsをフォローしない
    };
  };

  # ===========================================================================
  # 出力（システム設定）
  # ===========================================================================
  outputs = { self, nixpkgs, home-manager, lanzaboote, ... }: {
    nixosConfigurations = {

      # ─────────────────────────────────────────────────────────────
      # xc8: ノートPC (ThinkPad X1 Carbon 8th Gen)
      # ─────────────────────────────────────────────────────────────
      xc8 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/xc8                    # ホスト固有設定（ブート、ホスト名等）
          ./modules/common.nix           # 共通システム設定
          lanzaboote.nixosModules.lanzaboote  # Secure Bootサポート
          home-manager.nixosModules.home-manager
          {
            # VSCodeのバージョン固定オーバーレイ
            nixpkgs.overlays = [ (import ./overlays/vscode.nix) ];
            # Home Manager設定
            home-manager.useGlobalPkgs = true;      # システムのnixpkgsを使用
            home-manager.useUserPackages = true;    # ユーザーパッケージをシステムに統合
            home-manager.backupFileExtension = "backup";  # 既存ファイルのバックアップ拡張子
            # ホスト固有のディスプレイ設定をHome Managerに渡す
            home-manager.extraSpecialArgs = import ./hosts/xc8/niri-output.nix;
            home-manager.users.tagawa = import ./modules/home/tagawa.nix;
          }
        ];
      };

      # ─────────────────────────────────────────────────────────────
      # r995: デスクトップ（開発用）
      # ─────────────────────────────────────────────────────────────
      # Ryzen 9950X + AMD Radeon Graphics のハイエンドデスクトップ
      r995 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/r995                   # ホスト固有設定（ブート、GPU、ホスト名等）
          ./modules/common.nix           # 共通システム設定
          lanzaboote.nixosModules.lanzaboote  # Secure Bootサポート
          home-manager.nixosModules.home-manager
          {
            # VSCodeのバージョン固定オーバーレイ
            nixpkgs.overlays = [ (import ./overlays/vscode.nix) ];
            # Home Manager設定
            home-manager.useGlobalPkgs = true;      # システムのnixpkgsを使用
            home-manager.useUserPackages = true;    # ユーザーパッケージをシステムに統合
            home-manager.backupFileExtension = "backup";  # 既存ファイルのバックアップ拡張子
            # ホスト固有のディスプレイ設定をHome Managerに渡す
            home-manager.extraSpecialArgs = import ./hosts/r995/niri-output.nix;
            home-manager.users.tagawa = import ./modules/home/tagawa.nix;
          }
        ];
      };
    };
  };
}
