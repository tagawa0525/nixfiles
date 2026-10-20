# =============================================================================
# mozc: dictionary_tool.ui のクラス名から先頭の `::` を除く
# =============================================================================
# nixpkgs の Qt 更新後、uic が `::mozc::gui::DictionaryContentTableWidget` のように
# 先頭が `::` のクラス名を "Invalid class name" として拒否し、mozc のビルドが
# 失敗する（src/gui/dictionary_tool/dictionary_tool.ui の 2 か所）。
# 生成コードは名前空間の外で使われるため、`::` を外しても意味は変わらない。
#
# 撤去する場合:
#   mozc が上流で修正されるか nixpkgs 側で対処されたら、
#   modules/profiles/workstation.nix の import 行と本ファイルを削除する。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      mozc = prev.mozc.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/gui/dictionary_tool/dictionary_tool.ui \
            --replace-fail '"::mozc::gui::' '"mozc::gui::' \
            --replace-fail '<class>::mozc::gui::' '<class>mozc::gui::'
        '';
      });
    })
  ];
}
