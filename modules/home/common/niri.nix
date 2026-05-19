# =============================================================================
# Niriウィンドウマネージャ設定
# =============================================================================
# NiriはWaylandネイティブのスクロール型タイリングウィンドウマネージャ。
# ワークスペースが縦方向に無限スクロールする独特のUI。
#
# ホスト固有のディスプレイ設定は extraSpecialArgs 経由で渡されます。
# 参照: hosts/<hostname>/niri-output.nix
#
# キーバインドのカスタマイズは binds セクションで行います。
# =============================================================================
{
  niriOutputConfig ? "",
  ...
}:

{
  xdg.configFile."niri/config.kdl".text = ''
    // ==========================================================================
    // Niri設定ファイル
    // ==========================================================================
    // KDL形式（https://kdl.dev/）
    // 設定リロード: niri msg reload-config
    // ==========================================================================

    // ─────────────────────────────────────────────────────────────
    // 入力デバイス設定
    // ─────────────────────────────────────────────────────────────
    input {
        keyboard {
            xkb {
                // キーボードレイアウト設定
                // 例: layout "us,jp"
            }
            numlock  // NumLockをデフォルトでON
        }

        touchpad {
            tap           // タップでクリック
            natural-scroll // 自然なスクロール方向（スマホと同じ）
        }

        mouse {
            // マウス設定
        }

        trackpoint {
            // トラックポイント設定
        }
    }

    // ─────────────────────────────────────────────────────────────
    // ディスプレイ設定（ホスト固有）
    // ─────────────────────────────────────────────────────────────
    // hosts/<hostname>/niri-output.nix から挿入される
    ${niriOutputConfig}

    // ─────────────────────────────────────────────────────────────
    // レイアウト設定
    // ─────────────────────────────────────────────────────────────
    layout {
        gaps 16  // ウィンドウ間のギャップ（ピクセル）
        center-focused-column "never"  // フォーカス列を中央に配置しない

        // ウィンドウ幅のプリセット（Mod+Rで切り替え）
        preset-column-widths {
            proportion 0.33333  // 1/3幅
            proportion 0.5      // 1/2幅
            proportion 0.66667  // 2/3幅
        }

        default-column-width { proportion 0.5; }  // デフォルトは画面の半分

        // フォーカス中のウィンドウの枠線
        focus-ring {
            width 4
            active-color "#7fc8ff"    // アクティブ時（水色）
            inactive-color "#505050"  // 非アクティブ時（グレー）
        }

        // ウィンドウの境界線（デフォルトOFF）
        border {
            off
            width 4
            active-color "#ffc87f"
            inactive-color "#505050"
            urgent-color "#9b0000"
        }

        // ウィンドウの影
        shadow {
            softness 30
            spread 5
            offset x=0 y=5
            color "#0007"
        }

        struts {
            // 画面端の余白設定
        }
    }

    // ─────────────────────────────────────────────────────────────
    // 起動時に実行するコマンド
    // ─────────────────────────────────────────────────────────────
    spawn-at-startup "waybar"  // ステータスバー

    // ホットキーオーバーレイ（Mod+?で表示）
    hotkey-overlay {
    }

    // スクリーンショット保存先
    screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

    // アニメーション設定
    animations {
    }

    // ─────────────────────────────────────────────────────────────
    // ウィンドウルール
    // ─────────────────────────────────────────────────────────────
    // 特定のアプリに対するデフォルト動作を設定

    // WezTermは幅プリセットを使用しない
    window-rule {
        match app-id=r#"^org\.wezfurlong\.wezterm$"#
        default-column-width {}
    }

    // FirefoxのPicture-in-Pictureはフローティング
    window-rule {
        match app-id=r#"firefox$"# title="^Picture-in-Picture$"
        open-floating true
    }

    // ─────────────────────────────────────────────────────────────
    // キーバインド
    // ─────────────────────────────────────────────────────────────
    // Mod = Super (Windowsキー)
    binds {
        // ヘルプ表示
        Mod+Shift+Slash { show-hotkey-overlay; }

        // アプリケーション起動
        Mod+T hotkey-overlay-title="Open a Terminal: alacritty + tmux" { spawn "alacritty" "-e" "local-tmux"; }
        Mod+D hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }
        Super+Alt+L hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }

        // スクリーンリーダー切り替え
        Super+Alt+S allow-when-locked=true hotkey-overlay-title=null { spawn-sh "pkill orca || exec orca"; }

        // 音量調整（ロック中も有効）
        XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"; }
        XF86AudioMute        allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
        XF86AudioMicMute     allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }

        // メディア操作
        XF86AudioPlay        allow-when-locked=true { spawn-sh "playerctl play-pause"; }
        XF86AudioStop        allow-when-locked=true { spawn-sh "playerctl stop"; }
        XF86AudioPrev        allow-when-locked=true { spawn-sh "playerctl previous"; }
        XF86AudioNext        allow-when-locked=true { spawn-sh "playerctl next"; }

        // 画面輝度調整
        XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+10%"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "10%-"; }

        // オーバービュー（全ウィンドウ表示）
        Mod+O repeat=false { toggle-overview; }

        // ウィンドウを閉じる
        Mod+Q repeat=false { close-window; }

        // フォーカス移動（矢印キー）
        Mod+Left  { focus-column-left; }
        Mod+Down  { focus-window-down; }
        Mod+Up    { focus-window-up; }
        Mod+Right { focus-column-right; }
        // フォーカス移動（Vim風キー）
        Mod+H     { focus-column-left; }
        Mod+J     { focus-window-down; }
        Mod+K     { focus-window-up; }
        Mod+L     { focus-column-right; }

        // ウィンドウ移動（矢印キー）
        Mod+Ctrl+Left  { move-column-left; }
        Mod+Ctrl+Down  { move-window-down; }
        Mod+Ctrl+Up    { move-window-up; }
        Mod+Ctrl+Right { move-column-right; }
        // ウィンドウ移動（Vim風キー）
        Mod+Ctrl+H     { move-column-left; }
        Mod+Ctrl+J     { move-window-down; }
        Mod+Ctrl+K     { move-window-up; }
        Mod+Ctrl+L     { move-column-right; }

        // 最初/最後の列にフォーカス/移動
        Mod+Home { focus-column-first; }
        Mod+End  { focus-column-last; }
        Mod+Ctrl+Home { move-column-to-first; }
        Mod+Ctrl+End  { move-column-to-last; }

        // モニター間のフォーカス移動
        Mod+Shift+Left  { focus-monitor-left; }
        Mod+Shift+Down  { focus-monitor-down; }
        Mod+Shift+Up    { focus-monitor-up; }
        Mod+Shift+Right { focus-monitor-right; }
        Mod+Shift+H     { focus-monitor-left; }
        Mod+Shift+J     { focus-monitor-down; }
        Mod+Shift+K     { focus-monitor-up; }
        Mod+Shift+L     { focus-monitor-right; }

        // モニター間のウィンドウ移動
        Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+Down  { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+Up    { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
        Mod+Shift+Ctrl+H     { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+J     { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+K     { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+L     { move-column-to-monitor-right; }

        // ワークスペース移動
        Mod+Page_Down      { focus-workspace-down; }
        Mod+Page_Up        { focus-workspace-up; }
        Mod+U              { focus-workspace-down; }
        Mod+I              { focus-workspace-up; }
        Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
        Mod+Ctrl+Page_Up   { move-column-to-workspace-up; }
        Mod+Ctrl+U         { move-column-to-workspace-down; }
        Mod+Ctrl+I         { move-column-to-workspace-up; }

        // ワークスペース自体の移動
        Mod+Shift+Page_Down { move-workspace-down; }
        Mod+Shift+Page_Up   { move-workspace-up; }
        Mod+Shift+U         { move-workspace-down; }
        Mod+Shift+I         { move-workspace-up; }

        // マウスホイールでワークスペース移動
        Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
        Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
        Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
        Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

        // マウスホイールで列移動
        Mod+WheelScrollRight      { focus-column-right; }
        Mod+WheelScrollLeft       { focus-column-left; }
        Mod+Ctrl+WheelScrollRight { move-column-right; }
        Mod+Ctrl+WheelScrollLeft  { move-column-left; }

        Mod+Shift+WheelScrollDown      { focus-column-right; }
        Mod+Shift+WheelScrollUp        { focus-column-left; }
        Mod+Ctrl+Shift+WheelScrollDown { move-column-right; }
        Mod+Ctrl+Shift+WheelScrollUp   { move-column-left; }

        // 数字キーでワークスペース切り替え
        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+6 { focus-workspace 6; }
        Mod+7 { focus-workspace 7; }
        Mod+8 { focus-workspace 8; }
        Mod+9 { focus-workspace 9; }
        // 数字キーでワークスペースに移動
        Mod+Ctrl+1 { move-column-to-workspace 1; }
        Mod+Ctrl+2 { move-column-to-workspace 2; }
        Mod+Ctrl+3 { move-column-to-workspace 3; }
        Mod+Ctrl+4 { move-column-to-workspace 4; }
        Mod+Ctrl+5 { move-column-to-workspace 5; }
        Mod+Ctrl+6 { move-column-to-workspace 6; }
        Mod+Ctrl+7 { move-column-to-workspace 7; }
        Mod+Ctrl+8 { move-column-to-workspace 8; }
        Mod+Ctrl+9 { move-column-to-workspace 9; }

        // ウィンドウを列に吸収/排出
        Mod+BracketLeft  { consume-or-expel-window-left; }
        Mod+BracketRight { consume-or-expel-window-right; }

        Mod+Comma  { consume-window-into-column; }
        Mod+Period { expel-window-from-column; }

        // ウィンドウサイズ変更
        Mod+R { switch-preset-column-width; }  // プリセット幅を切り替え
        Mod+Shift+R { switch-preset-window-height; }
        Mod+Ctrl+R { reset-window-height; }
        Mod+F { maximize-column; }  // 列を最大化
        Mod+Shift+F { fullscreen-window; }  // フルスクリーン

        Mod+Ctrl+F { expand-column-to-available-width; }

        // ウィンドウを中央に配置
        Mod+C { center-column; }
        Mod+Ctrl+C { center-visible-columns; }

        // 幅/高さの微調整
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

        Mod+Shift+Minus { set-window-height "-10%"; }
        Mod+Shift+Equal { set-window-height "+10%"; }

        // フローティングウィンドウ
        Mod+V       { toggle-window-floating; }  // フローティング切り替え
        Mod+Shift+V { switch-focus-between-floating-and-tiling; }

        // タブ表示
        Mod+W { toggle-column-tabbed-display; }

        // スクリーンショット
        Print { screenshot; }           // 範囲選択
        Ctrl+Print { screenshot-screen; }  // 画面全体
        Alt+Print { screenshot-window; }   // ウィンドウ

        // キーボードショートカット無効化の切り替え
        Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }

        // Niri終了
        Mod+Shift+E { quit; }
        Ctrl+Alt+Delete { quit; }

        // モニター電源OFF
        Mod+Shift+P { power-off-monitors; }
    }
  '';
}
