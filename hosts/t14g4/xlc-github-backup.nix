# =============================================================================
# xlc の GitHub へのバックアップ（ADR-0035）
# =============================================================================
# r995 の xlc（作業の origin）のブランチとタグを、1 時間ごとに公開リポジトリ
# github.com/tagawa0525/xlc にミラーする。r995 で rebase・削除したブランチも反映する
# （force と prune）。作業用の clone の remote には触れず、専用の bare リポジトリ
# を中継に使う。
# =============================================================================
{ pkgs, ... }:

let
  xlc-github-backup = pkgs.writeShellApplication {
    name = "xlc-github-backup";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      mirror="$HOME/.local/state/xlc-github-backup/xlc.git"
      if [ ! -d "$mirror" ]; then
        git init --bare --quiet "$mirror"
      fi
      # refs/* をまとめてコピーする --mirror を使わないのは、r995 の作業用リポジトリの
      # refs/stash などを公開リポジトリに出さないため。heads と tags だけを送る
      refspecs=('+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*')
      git -C "$mirror" fetch --quiet --prune r995:/home/tagawa/github/xlc "''${refspecs[@]}"
      git -C "$mirror" push --quiet --prune git@github.com:tagawa0525/xlc.git "''${refspecs[@]}"
    '';
  };
in
{
  home-manager.users.tagawa.systemd.user = {
    services.xlc-github-backup = {
      Unit.Description = "Back up xlc from r995 to GitHub";
      Service = {
        Type = "oneshot";
        ExecStart = "${xlc-github-backup}/bin/xlc-github-backup";
      };
    };
    timers.xlc-github-backup = {
      Unit.Description = "Back up xlc from r995 to GitHub hourly";
      Timer = {
        OnCalendar = "hourly";
        # ノート PC で止まっていた間の分を、起動後に 1 回実行する
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
