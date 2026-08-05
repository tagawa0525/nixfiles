# =============================================================================
# Zellij設定
# =============================================================================
# ターミナル多重化ツールの設定と接続スクリプト（tmuxからの移行検証用に併存）
# - zellij-slots: スロット式タブ管理プラグイン（./zellij-slots からビルド）
# - local-zellij: ローカルZellijセッションに接続
# - ssh-*-zellij: リモートホストのZellijセッションに接続
#
# tmuxとの対応:
# - グループセッション+未接続回収 → 1セッションへの多重アタッチ（標準機能）
# - window番号の固定運用          → タブ名をスロット番号として扱う（プラグイン）
# - prefix C-\ と各キーバインド   → locked/tmuxモードで再現
# - status-left/right             → zjstatusプラグイン
# =============================================================================
{ pkgs, lib, ... }:

let
  # ===========================================================================
  # スロット式タブ管理プラグイン
  # ===========================================================================
  # タブ番号の優先順位（3 4 2 8 7 9 5 6 1 0）はプラグイン側に定義がある
  # （tmux.nix の windowPriority と同じ値。詳細は zellij-slots/src/main.rs）
  zellij-slots = pkgs.pkgsCross.wasm32-wasip1.rustPlatform.buildRustPackage {
    pname = "zellij-slots";
    version = "0.1.0";
    src = ./zellij-slots;
    cargoLock.lockFile = ./zellij-slots/Cargo.lock;
    # nixpkgsのZellijプラグイン群と同じリンカ設定
    # (nixpkgs: pkgs/by-name/ze/zellij/plugins/rust/default.nix)
    nativeBuildInputs = [ pkgs.pkgsCross.wasm32-wasip1.lld ];
    env.RUSTFLAGS = "-C linker=wasm-ld";
    # wasmターゲットのテストは実行できない。ロジックのユニットテストは
    # ホスト向けの cargo test で、結合は tests/local-zellij.sh で検証する
    doCheck = false;
  };
  slotsPlugin = "file:${zellij-slots}/bin/zellij-slots.wasm";

  # スロットNへのジャンプ（プレフィックス+数字。tmuxのselect-window相当）
  gotoBinds = lib.concatMapStrings (n: ''
    bind "${n}" { MessagePlugin "${slotsPlugin}" { name "slots"; payload "goto:${n}"; }; SwitchToMode "Locked"; }
  '') (map toString (lib.range 0 9));
in
{
  # ===========================================================================
  # Zellij本体の設定
  # ===========================================================================
  # キーバインドはtmuxの運用に合わせる:
  # - 通常はlockedモード（tmux同様、プレフィックス以外を素通しする）
  # - Ctrl+\ でプレフィックス（tmuxモード）に入り、1キー実行して戻る
  xdg.configFile."zellij/config.kdl".text = ''
    keybinds clear-defaults=true {
        locked {
            bind "Ctrl \\" { SwitchToMode "Tmux"; }
        }
        tmux {
            // 2回押しで直前のタブに戻る（tmuxのlast-window相当）
            bind "Ctrl \\" { ToggleTab; SwitchToMode "Locked"; }
            bind "Esc" "Enter" { SwitchToMode "Locked"; }
            // 優先順位で空いているスロット番号に新規タブを作成
            bind "c" { MessagePlugin "${slotsPlugin}" { name "slots"; payload "new"; }; SwitchToMode "Locked"; }
    ${gotoBinds}
            bind "d" { Detach; }
            bind "[" { SwitchToMode "Scroll"; }
            bind "\"" { NewPane "Down"; SwitchToMode "Locked"; }
            bind "%" { NewPane "Right"; SwitchToMode "Locked"; }
            bind "x" { CloseFocus; SwitchToMode "Locked"; }
            bind "z" { ToggleFocusFullscreen; SwitchToMode "Locked"; }
            bind "," { SwitchToMode "RenameTab"; TabNameInput 0; }
            bind "o" { FocusNextPane; SwitchToMode "Locked"; }
            bind "Left" { MoveFocus "Left"; SwitchToMode "Locked"; }
            bind "Right" { MoveFocus "Right"; SwitchToMode "Locked"; }
            bind "Down" { MoveFocus "Down"; SwitchToMode "Locked"; }
            bind "Up" { MoveFocus "Up"; SwitchToMode "Locked"; }
        }
        // 以下のモードはデフォルト設定の写し（Normalへの遷移をLockedに変更）
        scroll {
            bind "q" "Esc" "Ctrl c" { ScrollToBottom; SwitchToMode "Locked"; }
            bind "e" { EditScrollback; SwitchToMode "Locked"; }
            bind "s" "/" { SwitchToMode "EnterSearch"; SearchInput 0; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
        }
        search {
            bind "q" "Esc" "Ctrl c" { ScrollToBottom; SwitchToMode "Locked"; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "n" { Search "down"; }
            bind "p" { Search "up"; }
            bind "c" { SearchToggleOption "CaseSensitivity"; }
            bind "w" { SearchToggleOption "Wrap"; }
            bind "o" { SearchToggleOption "WholeWord"; }
        }
        entersearch {
            bind "Ctrl c" "Esc" { SwitchToMode "Scroll"; }
            bind "Enter" { SwitchToMode "Search"; }
        }
        renametab {
            bind "Enter" { SwitchToMode "Locked"; }
            bind "Esc" { UndoRenameTab; SwitchToMode "Locked"; }
        }
    }

    // スロット管理プラグインをセッション開始時にバックグラウンドでロードする
    load_plugins {
        "${slotsPlugin}"
    }

    // tmux同様、通常時はすべてのキーをアプリに素通しする
    default_mode "locked"
    // tmux内ではfishを使用（デフォルトシェルはbashなのでVSCode-Serverも問題なし）
    default_shell "${pkgs.fish}/bin/fish"
    // 新規セッションはスロット3の1タブから始まる（layouts/slots.kdl）
    default_layout "slots"
    scroll_buffer_size 50000
    // tmuxに枠線はないので合わせる（ペイン分割時は色付きの境界線が入る）
    pane_frames false
    // 起動時のTipsやリリースノートで初回タブを汚さない
    show_startup_tips false
    show_release_notes false
  '';

  # ===========================================================================
  # デフォルトレイアウト
  # ===========================================================================
  # - 初期タブはスロット「3」（tmuxのmove-window -t :3 相当）
  # - ステータスラインはzjstatusで tmux の status-left/right を再現
  xdg.configFile."zellij/layouts/slots.kdl".text = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="file:${pkgs.zellijPlugins.zjstatus}" {
                    format_left   "{session} | {tabs}"
                    format_right  "{mode}{datetime}"
                    format_space  ""

                    mode_locked       ""
                    mode_tmux         "#[bg=yellow,fg=black] ^\\ "
                    mode_scroll       "#[bg=blue,fg=black] SCROLL "
                    mode_enter_search "#[bg=blue,fg=black] SEARCH "
                    mode_search       "#[bg=blue,fg=black] SEARCH "
                    mode_rename_tab   "#[bg=blue,fg=black] RENAME "

                    tab_normal " {name} "
                    tab_active "#[bg=white,fg=black] {name} "

                    datetime          "{format}"
                    datetime_format   "%Y/%m/%d %H:%M"
                    datetime_timezone "Asia/Tokyo"
                }
            }
        }
        tab name="3" focus=true
    }
  '';

  # ===========================================================================
  # Zellij接続スクリプト
  # ===========================================================================
  home.packages = [
    pkgs.zellij
    # ローカルZellij起動。セッションがあれば多重アタッチ（各クライアントが
    # 独立したフォーカスを持つ）、なければslotsレイアウトで新規作成
    (pkgs.writeShellScriptBin "local-zellij" ''
      exec ${pkgs.zellij}/bin/zellij attach --create main
    '')
    # リモートホストへのZellij接続
    (pkgs.writeShellScriptBin "ssh-r995-zellij" ''
      ssh -t r995 local-zellij
    '')
  ];

  # ===========================================================================
  # Zellij接続用ランチャーエントリ
  # ===========================================================================
  xdg.desktopEntries = {
    local-zellij = {
      name = "Terminal (zellij)";
      comment = "AlacrittyでZellijセッションを起動";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e local-zellij";
      terminal = false;
      categories = [
        "System"
        "TerminalEmulator"
      ];
    };
    ssh-r995-zellij = {
      name = "SSH to r995 (zellij)";
      comment = "Tailscale経由でr995にSSH接続しZellijにアタッチ";
      icon = "utilities-terminal";
      exec = "${pkgs.alacritty}/bin/alacritty -e ssh-r995-zellij";
      terminal = false;
      categories = [
        "Network"
        "RemoteAccess"
      ];
    };
  };
}
