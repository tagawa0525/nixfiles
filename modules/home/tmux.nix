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
  # window番号の優先順位（押しやすい順）
  # ===========================================================================
  windowPriority = "3 4 2 8 7 9 5 6 1 0";

  # ===========================================================================
  # 優先順位で空いているwindow番号にnew-windowを作成
  # ===========================================================================
  tmuxNewWindowCmd = ''
    existing=$(tmux list-windows -F '#I' 2>/dev/null)
    for n in ${windowPriority}; do
      if ! echo "$existing" | grep -q "^$n$"; then
        tmux new-window -t ":$n"
        exit 0
      fi
    done
    tmux new-window
  '';

  # ===========================================================================
  # tmux接続の共通ロジック
  # ===========================================================================
  # 既存セッションがあれば新規windowを作成してグループセッションで接続
  # なければ新規セッション作成
  tmuxConnectCmd = ''
    if tmux has-session -t main 2>/dev/null; then
      # 優先順位で空いているwindow番号を探す
      existing=$(tmux list-windows -t main -F '#I' 2>/dev/null)
      for n in ${windowPriority}; do
        if ! echo "$existing" | grep -q "^$n$"; then
          exec tmux new-session -t main \; new-window -t ":$n"
        fi
      done
      # 全て埋まっていたら通常のnew-window
      exec tmux new-session -t main \; new-window
    else
      # 新規セッション：window 0で作成後、window 3に移動
      tmux new-session -d -s main
      tmux move-window -s main:0 -t main:3
      exec tmux attach -t main
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

      # 新規window作成を押しやすい番号順で（3, 4, 2, 8, 7, 9, 5, 6, 1, 0）
      bind c run-shell 'tmux-new-window-smart'

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
    # 優先順位でnew-windowを作成（tmux内から呼び出し用）
    (pkgs.writeShellScriptBin "tmux-new-window-smart" tmuxNewWindowCmd)
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
