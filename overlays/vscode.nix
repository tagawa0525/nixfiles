final: prev: {
  vscode = prev.vscode.overrideAttrs (oldAttrs: rec {
    version = "1.108.0";
    src = final.fetchurl {
      url = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
      sha256 = "02fzc7js802iydf1rkrxarn34f15nmqnrg8h6z0jv1y5y46rsk6v";
      name = "vscode-${version}.tar.gz";
    };
  });
}
