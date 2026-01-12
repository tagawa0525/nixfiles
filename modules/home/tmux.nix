# =============================================================================
# Tmux設定
# =============================================================================
# ターミナル多重化ツールの設定とtmux接続スクリプト
# - programs.tmux: tmux本体の設定
# - local-tmux: ローカルtmuxセッションに接続
# - ssh-*-tmux: リモートホストのtmuxセッションに接続
# =============================================================================
{ pkgs, ... }:

let
  # ===========================================================================
  # tmux接続の共通ロジック
  # ===========================================================================
  # 既存セッションがあれば新規windowを作成してグループセッションで接続
  # なければ新規セッション作成
  tmuxConnectCmd = ''
    if tmux has-session -t main 2>/dev/null; then
      tmux new-session -t main \; new-window
    else
      tmux new-session -s main
    fi
  '';

  # SSH経由でtmux接続するスクリプトを生成
  mkSshTmux = name: host:
    pkgs.writeShellScriptBin name ''
      ssh -t ${host} '${tmuxConnectCmd}'
    '';

  # SSH tmux用デスクトップエントリを生成
  mkSshTmuxEntry = { name, comment, scriptName }:
    {
      inherit name comment;
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e ${scriptName}";
      terminal = false;
      categories = [ "Network" "RemoteAccess" ];
    };
in
{
  # ===========================================================================
  # Tmux本体の設定
  # ===========================================================================
  programs.tmux = {
    enable = true;
    # tmux内ではfishを使用（デフォルトシェルはbashなのでVSCode-Serverも問題なし）
    shell = "${pkgs.fish}/bin/fish";
    # エスケープキーをCtrl+\に変更（Ctrl+Bから）
    prefix = "C-\\\\";
    # その他の設定
    escapeTime = 0; # Escキーの遅延をなくす
    historyLimit = 50000;
    mouse = true; # Alacrittyはマウス対応なので有効化
    terminal = "tmux-256color";
    extraConfig = ''
      # Ctrl+\ 2回押しで前のウィンドウに戻る
      bind C-\\ last-window

      # ビジュアルベル無効化
      set -g visual-bell off

      # ウィンドウ番号の自動リナンバリング無効化
      set -g renumber-windows off

      # ステータスライン設定
      set -g status-left "#{session_name} | "
      set -g status-right "%Y/%m/%d %H:%M"
      set -g window-status-current-style bg=white

      # クリップボード統合（Alacrittyで使用）
      set -g set-clipboard on
    '';
  };

  # ===========================================================================
  # tmux接続スクリプト
  # ===========================================================================
  home.packages = [
    # ローカルtmux起動
    (pkgs.writeShellScriptBin "local-tmux" tmuxConnectCmd)
    # リモートホストへのtmux接続
    (mkSshTmux "ssh-r995-tmux" "r995")
    (mkSshTmux "ssh-xc8-tmux" "xc8")
  ];

  # ===========================================================================
  # tmux接続用ランチャーエントリ
  # ===========================================================================
  xdg.desktopEntries = {
    # ローカルtmux起動
    local-tmux = {
      name = "Terminal (tmux)";
      comment = "Alacrittyでtmuxセッションを起動";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e local-tmux";
      terminal = false;
      categories = [ "System" "TerminalEmulator" ];
    };
    # リモートホストへのtmux接続
    ssh-r995 = mkSshTmuxEntry {
      name = "SSH to r995 (tmux)";
      comment = "Tailscale経由でr995にSSH接続しtmuxにアタッチ";
      scriptName = "ssh-r995-tmux";
    };
    ssh-xc8 = mkSshTmuxEntry {
      name = "SSH to xc8 (tmux)";
      comment = "Tailscale経由でxc8にSSH接続しtmuxにアタッチ";
      scriptName = "ssh-xc8-tmux";
    };
  };
}
