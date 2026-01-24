# =============================================================================
# カスタムVSCode拡張機能
# =============================================================================
# nixpkgsに含まれていない拡張機能をここで定義します
# =============================================================================
{ pkgs, ... }:

{
  # VS Code Speech 日本語言語パック
  vscode-speech-language-pack-ja-jp = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "vscode-speech-language-pack-ja-jp";
      publisher = "ms-vscode";
      version = "0.5.0";
      sha256 = "sha256-gbesiqyKWPlEPDyAmTgDSbMN9rWRkq1Trsih0gLgPr0=";
    };
    meta = {
      description = "Japanese (Japan) language support for VS Code Speech";
      homepage = "https://marketplace.visualstudio.com/items?itemName=ms-vscode.vscode-speech-language-pack-ja-jp";
      license = pkgs.lib.licenses.unfree;
    };
  };
}
