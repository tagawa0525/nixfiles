# =============================================================================
# copilot-cli: patchelf を interpreter の書き換えだけにする
# =============================================================================
# llm-agents.nix の copilot-cli (1.0.100) は patchelf で interpreter と rpath を
# 同時に書き換える。これで program header が再配置され、Node SEA の本体が
# segfault する（installCheck の `copilot --version` が exit code 139 で失敗）。
# interpreter だけ、または rpath だけの書き換えなら動く（1.0.100 で確認）。
# rpath は wrapper の LD_LIBRARY_PATH が同じ場所を指すため不要である。
#
# 撤去する場合:
#   上流（numtide/llm-agents.nix）が同時書き換えをやめたら、flake.nix の
#   import 行と本ファイルを削除する。
# =============================================================================
{ lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (
      final: prev:
      lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
        llm-agents = prev.llm-agents // {
          copilot-cli = prev.llm-agents.copilot-cli.overrideAttrs (old: {
            # installPhase 末尾の postInstall 時点のカレントは展開したソースの根で、
            # 元の copilot が残っている。それを interpreter だけ書き換えて差し替える
            postInstall = (old.postInstall or "") + ''
              install -m755 copilot "$out/lib/copilot-cli/copilot"
              patchelf --set-interpreter "$(cat ${final.stdenv.cc}/nix-support/dynamic-linker)" \
                "$out/lib/copilot-cli/copilot"
            '';
          });
        };
      }
    )
  ];
}
