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
  # 未接続セッションがあれば回収、なければ新規windowを作成してグループ接続
  # どちらも無ければ新規セッション作成
  #
  # `main` はグループの起点なので destroy-unattached の対象外にする。
  # これがないと detach 時に `main` 自身が破棄され、残るのは `main-1` の
  # ような番号付きセッションだけになる。その状態で2つ以上並存すると
  # `has-session -t main` の前方一致が複数ヒットして失敗し、下のelse側で
  # グループと無関係な新規`main`を作ってしまう（既存windowから切り離される）。
  # 同じ理由でセッション指定は `=` を付けて完全一致にする。
  # ただし set-option だけは例外で、tmux(1) の記法が
  # `set-option [-aFgopqsuUw] [-t target-pane]` と target-pane のため
  # `=main` を渡すと `no such session: =main` になる（tmux 3.7で確認）。
  # そこだけ素の `main` を渡す（完全一致は前方一致より優先されるので安全）。
  tmuxConnectCmd = ''
    if tmux has-session -t '=main' 2>/dev/null; then
      # アンカー保護はセッション単位の設定でサーバに永続しないため、接続の
      # たびに設定し直す。この変更より前から動いているサーバや、local-tmux
      # を経由せず作られた`main`が無防備なまま残るのを防ぐ（冪等）。
      tmux set-option -t main destroy-unattached off

      # クライアントが繋がっていないセッションがあれば回収して再利用する。
      # destroy-unattached の対象外である `main` は detach 後も残るため、
      # 回収しないと接続のたびに `main-1` を作り直すことになる。
      # session_group は最初の1接続だけ空になるため、アンカーの main 自身も
      # 対象に含める（区切りが空でも列がずれないよう | で分割）。
      # 複数ある場合は最後にアタッチしたものを選ぶ。名前順だと常に main が
      # 選ばれ、切断前の current window に戻れないため。
      # session_last_attached は detach では更新されない（アタッチ時刻のまま。
      # tmux 3.7で確認）ので「最後に切断した」とは一致しないが、ssh 切断からの
      # 復帰では直前まで使っていたセッションが最後にアタッチしたものになる
      orphan=$(tmux list-sessions \
        -F '#{session_attached}|#{session_group}|#{session_last_attached}|#{session_name}' 2>/dev/null \
        | awk -F'|' '$1 == 0 && ($2 == "main" || $4 == "main")' \
        | sort -t'|' -k3,3nr \
        | head -n 1 \
        | cut -d'|' -f4)
      if [ -n "$orphan" ]; then
        # 回収対象が直前に消えた場合は通常経路にフォールバックする。ただし
        # kill-server でサーバーごと落ちた場合まで作り直すと、ユーザーが
        # 終了させたサーバーを復活させてしまうので、サーバーの生存を確認する
        # （tmux 3.7 で実測した attach の終了コード: セッション不在=1、
        #   attach中のkill-server=1、通常のデタッチ=0、対象セッションのkill=0）
        # 失敗はフォールバックで吸収するので、紛らわしいエラーは出さない
        tmux attach -t "=$orphan" 2>/dev/null && exit 0
        tmux has-session -t '=main' 2>/dev/null || exit 1
      fi

      # 優先順位で空いているwindow番号を探す
      existing=$(tmux list-windows -t '=main' -F '#I' 2>/dev/null)
      for n in ${windowPriority}; do
        if ! echo "$existing" | grep -q "^$n$"; then
          exec tmux new-session -t '=main' \; new-window -t ":$n"
        fi
      done
      # 全て埋まっていたら通常のnew-window
      exec tmux new-session -t '=main' \; new-window
    else
      # 新規セッション：window 0で作成後、window 3に移動
      tmux new-session -d -s main
      tmux set-option -t main destroy-unattached off
      tmux move-window -s '=main:0' -t '=main:3'
      exec tmux attach -t '=main'
    fi
  '';

  # SSH経由でtmux接続するスクリプトを生成
  # リモートホストにも同じNixOS設定があるので、local-tmuxを呼び出す
  mkSshTmux =
    name: host:
    pkgs.writeShellScriptBin name ''
      ssh -t ${host} local-tmux
    '';

  # SSH tmux用デスクトップエントリを生成
  mkSshTmuxEntry =
    {
      name,
      comment,
      scriptName,
    }:
    {
      inherit name comment;
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e ${scriptName}";
      terminal = false;
      categories = [
        "Network"
        "RemoteAccess"
      ];
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

      # detachしたグループセッションを自動破棄（グループ最後の1つは残す）
      # local-tmuxは接続ごとに `new-session -t main` でビュー用セッションを
      # 増やすが、端末を閉じてもdetachのまま残り続けるため。
      # ウィンドウはグループ内で共有されるので、ビューを破棄してもshellは死なない。
      set -g destroy-unattached keep-last

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
      categories = [
        "System"
        "TerminalEmulator"
      ];
    };
    # リモートホストへのtmux接続
    ssh-r995 = mkSshTmuxEntry {
      name = "SSH to r995 (tmux)";
      comment = "Tailscale経由でr995にSSH接続しtmuxにアタッチ";
      scriptName = "ssh-r995-tmux";
    };
  };
}
