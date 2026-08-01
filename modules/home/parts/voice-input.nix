# =============================================================================
# 音声入力 (voxtype + whisper.cpp)
# =============================================================================
# OS 全体（任意のアプリ）で使えるローカル音声入力。
# https://github.com/peteonrails/voxtype
#
# 仕組み:
#   - voxtype デーモンが常駐し、COSMIC のカスタムショートカット
#     (Super+V -> `voxtype record toggle`) で録音を開始/停止する
#   - 停止すると whisper.cpp（voxtype に内蔵、完全ローカル）が文字起こしし、
#     カーソル位置に貼り付ける
#
# 設計上の選択:
#   - ホットキーは voxtype 内蔵の evdev 監視ではなく COSMIC キーバインドで
#     制御する。evdev 監視は input グループ加入（= 全キーボードの生イベント
#     読み取り権限）が必要で、openlogi.nix で意図的に避けているキーロガー面を
#     開いてしまうため
#   - 出力は paste モード（wl-copy でクリップボードに置き Ctrl+V を打鍵）。
#     日本語（漢字かな交じり）はキーコード合成では入力できないため、
#     クリップボード経由が唯一確実な方式
#   - 貼り付け打鍵は dotool（uinput 直接）で行う。/dev/uinput へのアクセスは
#     openlogi.nix の uaccess ルールで既に開放済みなので追加権限は不要。
#     wtype は COSMIC の virtual-keyboard 実装で誤動作する報告があるため
#     driver_order から除外する
#
# 初回セットアップ（ホストごとに1回）:
#   モデルは初回使用時に ~/.local/share/voxtype/ へ自動ダウンロードされる。
#   手動で行う場合: `voxtype setup --download`
# =============================================================================
{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  # x1ng1 (4コア Tiger Lake) では large-v3-turbo の CPU 推論が遅すぎるため
  # small に落とす。認識精度は下がるが応答時間を優先する
  whisperModel = if osConfig.networking.hostName == "x1ng1" then "small" else "large-v3-turbo";
in
{
  # 依存ツールの追加インストールは不要: nixpkgs の voxtype は wrapProgram で
  # dotool / wl-clipboard / wtype（および X11 用の xclip / xdotool）を
  # 自身の PATH に注入している
  home.packages = [ pkgs.voxtype ];

  # ===========================================================================
  # voxtype 設定
  # ===========================================================================
  # 注意: voxtype はセクションの部分省略を許さない（missing field でパース
  # エラーになる）ため、同梱 default-config.toml の全セクションを明示する
  xdg.configFile."voxtype/config.toml".text = ''
    # `voxtype record toggle` と `voxtype status` に必須
    state_file = "auto"

    [hotkey]
    # COSMIC キーバインドから `voxtype record toggle` で制御するため無効化
    # （有効化には input グループ加入が必要になる。上部コメント参照）
    enabled = false
    key = "SCROLLLOCK"
    modifiers = []

    [audio]
    device = "default"
    sample_rate = 16000
    max_duration_secs = 60

    [whisper]
    model = "${whisperModel}"
    language = "ja"
    translate = false
    # 録音開始時にモデルをロードし、文字起こし後に解放する。
    # 常駐 RAM（large-v3-turbo で約 2GB）を節約する代わりに、
    # 使用のたびにロード時間（SSD なら 1〜2 秒）が加算される
    on_demand_loading = true

    [output]
    # クリップボードにコピーしてから貼り付けキーを打鍵する（日本語対応の要）
    mode = "paste"
    paste_keys = "ctrl+v"
    # 元のクリップボード内容を退避し、貼り付け後に復元する
    restore_clipboard = true
    # wtype（COSMIC で誤動作）と ydotool（要デーモン）を除外し、
    # dotool（uinput 直接）→ 失敗時はクリップボードに残すだけ、の順で試す
    driver_order = ["dotool", "clipboard"]
    fallback_to_clipboard = true
    type_delay_ms = 0
    pre_type_delay_ms = 0

    [output.notification]
    on_recording_start = true
    on_recording_stop = true
    on_transcription = true

    [status]
    icon_theme = "emoji"
  '';

  # ===========================================================================
  # COSMIC カスタムショートカット
  # ===========================================================================
  # Super+V で録音の開始/停止をトグルする。
  # デーモンへ SIGUSR1/SIGUSR2 を送るだけなので即座に返る
  xdg.configFile."cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom".text = ''
    {
        (modifiers: [Super], key: "v"): Spawn("${lib.getExe pkgs.voxtype} record toggle"),
    }
  '';

  # ===========================================================================
  # voxtype デーモン（systemd ユーザーサービス）
  # ===========================================================================
  # wl-copy が WAYLAND_DISPLAY を必要とするため graphical-session.target に
  # 紐付ける（cosmic-session が環境変数を systemd user manager に import する）
  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype voice-to-text daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.voxtype} daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
