# =============================================================================
# Zellij設定
# =============================================================================
# ターミナル多重化ツールの設定と接続スクリプト
# - zellij-slots: スロット式タブ管理プラグイン（./zellij-slots からビルド）
# - local-zellij: ローカルZellijセッションに接続
# - ssh-*-zellij: リモートホストのZellijセッションに接続
#
# 旧tmux運用との対応:
# - グループセッション+未接続回収 → 1セッションへの多重アタッチ（標準機能）
# - window番号の固定運用          → タブ名をスロット番号として扱う（プラグイン）
# - prefix C-\ と各キーバインド   → locked/tmuxモードで再現
# - status-left/right、window一覧 → zellij-slotsが描画（番号順ソート・
#                                   「N:実行中コマンド」表示・日時）
# =============================================================================
{ pkgs, lib, ... }:

let
  # ===========================================================================
  # スロット式タブ管理プラグイン
  # ===========================================================================
  # タブ番号の優先順位（3 4 2 8 7 9 5 6 1 0）はプラグイン側の
  # SLOT_PRIORITY（zellij-slots/src/main.rs）に定義がある。旧tmux運用と同じ値
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

  # スロットNへのジャンプ（プレフィックス+数字。旧tmuxのselect-window相当）。
  # プレフィックスからCtrlを離さず押した場合（Ctrl+N）でも効くよう両方束ねる。
  # プラグインを指定しないパイプは起動済みの全インスタンスへ配送され、
  # ステータスバーのうち「プレフィックスを押したクライアントのもの」だけが
  # 実行する。lockedへ戻すのもプラグイン側の仕事になる（先に戻すと押した
  # 本人を見分けられなくなるため）。詳細は zellij-slots/src/main.rs を参照
  gotoBinds = lib.concatMapStrings (n: ''
    bind "${n}" "Ctrl ${n}" { MessagePlugin { name "slots"; payload "goto:${n}"; }; }
  '') (map toString (lib.range 0 9));
in
{
  # ===========================================================================
  # Zellij本体の設定
  # ===========================================================================
  # キーバインドは旧tmuxの運用に合わせる:
  # - 通常はlockedモード（旧tmux同様、プレフィックス以外を素通しする）
  # - Ctrl+\ でプレフィックス（tmuxモード）に入り、1キー実行して戻る
  xdg.configFile."zellij/config.kdl".text = ''
    keybinds clear-defaults=true {
        // プレフィックスは2つの形式で届く:
        // - kitty keyboard protocol対応端末（Alacritty）: 「Ctrl \」
        // - 非対応端末（VSCodeターミナル等）: 生バイト0x1C。Zellij同梱の
        //   termwizはCtrl+A〜Z（0x01〜0x1A）しか変換せず、0x1Cは素の制御
        //   文字のまま届くため「\u{1c}」として併記する
        locked {
            bind "Ctrl \\" "\u{1c}" { SwitchToMode "Tmux"; }
        }
        tmux {
            // 2回押しで直前のタブに戻る（旧tmuxのlast-window相当）
            bind "Ctrl \\" "\u{1c}" { ToggleTab; SwitchToMode "Locked"; }
            bind "Esc" "Enter" { SwitchToMode "Locked"; }
            // 優先順位で空いているスロット番号に新規タブを作成。
            // 空きスロットの計算には最新のタブ一覧が要るので、状態が新鮮な
            // バックグラウンドのインスタンス（actor）に処理させる
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

    // 旧tmux同様、通常時はすべてのキーをアプリに素通しする
    default_mode "locked"
    // zellij内ではfishを使用（デフォルトシェルはbashなのでVSCode-Serverも問題なし）
    default_shell "${pkgs.fish}/bin/fish"
    // 新規セッションはスロット3の1タブから始まる（layouts/slots.kdl）
    default_layout "slots"
    scroll_buffer_size 50000
    // 旧tmuxに枠線はなかったので合わせる（ペイン分割時は色付きの境界線が入る）
    pane_frames false
    // 起動時のTipsやリリースノートで初回タブを汚さない
    show_startup_tips false
    show_release_notes false
  '';

  # ===========================================================================
  # デフォルトレイアウト
  # ===========================================================================
  # - 初期タブはスロット「3」（旧tmuxのmove-window -t :3 相当）
  # - ステータスラインはzellij-slotsが描画する。タブごとにインスタンス化され、
  #   キーバインドのMessagePluginパイプもこのインスタンス群が処理する
  xdg.configFile."zellij/layouts/slots.kdl".text = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                // role=bar は描画専用。パイプ（new/goto）は設定なしで起動される
                // バックグラウンドのシングルトンが処理する（main.rsの役割分離を参照）
                plugin location="${slotsPlugin}" {
                    role "bar"
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
  # タブラベルへのコマンド名通知（旧tmuxの#W相当）
  # ===========================================================================
  # Zellijはペインタイトルの変更（OSC）だけではプラグインにイベントを
  # 発行しないため、fishのフックでコマンドの開始（fish_preexec）と
  # プロンプト復帰（fish_prompt）をステータスバーへパイプで通知する。
  # プラグイン指定なしのパイプは起動済みの全インスタンスに届き、
  # 描画役のbarが取り込む
  programs.fish.interactiveShellInit = ''
    if set -q ZELLIJ; and set -q ZELLIJ_PANE_ID
      function __zellij_slots_notify --argument-names title
        # 隠れているタブのバーが処理を終えるまでCLIパイプはブロックする
        # ことがあるため、タイムアウトを付けてバックグラウンドで流す
        command ${pkgs.coreutils}/bin/timeout 2 ${pkgs.zellij}/bin/zellij pipe --name slots -- "title:$ZELLIJ_PANE_ID:$title" >/dev/null 2>&1 &
        disown
      end
      function __zellij_slots_preexec --on-event fish_preexec
        __zellij_slots_notify (string split -m1 ' ' -- $argv[1])[1]
      end
      function __zellij_slots_prompt --on-event fish_prompt
        __zellij_slots_notify fish
      end
    end
  '';

  # ===========================================================================
  # プラグイン権限の自動付与
  # ===========================================================================
  # rebuildでwasmのパスが変わる・プラグインの要求権限が増えると、Zellijは
  # 権限を再要求するが、承認UIは高さ1行のバー用ペインの中に描画されて実質
  # 見えず、プラグインは承認待ちのままブロックする（バーが空になり、
  # キーバインドも効かなくなる）。必要な権限は決まっているので、rebuild時に
  # 権限キャッシュへ直接シードする。同じwasmパスの既存エントリは内容が
  # 古い可能性があるため、スキップせずあるべき内容に書き直す（他プラグインの
  # エントリは保持）。Zellijはこのファイルを承認時に全量書き直すため互換。
  # 権限リストは src/main.rs の request_permission と一致させること
  # （乖離は tests/local-zellij.sh が実activationスクリプトでシードして検出する）。
  # activationは限られたPATHで実行されるため、外部コマンドはストアパスで参照する
  home.activation.zellijPluginPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    permissions="''${XDG_CACHE_HOME:-$HOME/.cache}/zellij/permissions.kdl"
    wasm="${zellij-slots}/bin/zellij-slots.wasm"
    desired="\"$wasm\" {"
    for p in ReadApplicationState ChangeApplicationState ReadCliPipes; do
      desired+=$'\n'"    $p"
    done
    desired+=$'\n'"}"
    current=""
    if [ -f "$permissions" ]; then
      current=$(${pkgs.coreutils}/bin/cat "$permissions")
    fi
    # Zellij側の書式ゆらぎで判定を逃さないよう、前後の空白を除いて比較する
    rest=$(printf '%s\n' "$current" | ${pkgs.gawk}/bin/awk -v start="\"$wasm\" {" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      trim($0) == start { skip=1; next }
      skip { if (trim($0) == "}") skip=0; next }
      { print }
    ')
    new="$rest"
    if [ -n "$new" ]; then
      new+=$'\n'
    fi
    new+="$desired"
    if [ "$new" != "$current" ]; then
      if [[ -v DRY_RUN ]]; then
        verboseEcho "Would seed zellij plugin permissions into $permissions"
      else
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$permissions")"
        printf '%s\n' "$new" > "$permissions"
      fi
    fi
  '';

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
