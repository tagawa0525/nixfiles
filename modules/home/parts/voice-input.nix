# =============================================================================
# 音声入力 (voxtype + SenseVoice)
# =============================================================================
# OS 全体（任意のアプリ）で使えるローカル音声入力。
# https://github.com/peteonrails/voxtype
#
# 仕組み:
#   - voxtype デーモンが常駐し、COSMIC のカスタムショートカット
#     (Super+V -> `voxtype record toggle`) で録音を開始/停止する
#   - 停止すると SenseVoice（ONNX、完全ローカル、日本語対応）が文字起こしし、
#     wtype がカーソル位置に直接タイプする
#
# 設計上の選択:
#   - ホットキーは voxtype 内蔵の evdev 監視ではなく COSMIC キーバインドで
#     制御する。evdev 監視は input グループ加入（= 全キーボードの生イベント
#     読み取り権限）が必要で、openlogi.nix で意図的に避けているキーロガー面を
#     開いてしまうため
#   - エンジンは whisper ではなく SenseVoice。whisper large-v3-turbo は
#     r995(16スレッド) でも数秒の発話に 8〜10 秒かかり、繰り返し幻覚
#     （同一フレーズの連発）も実音声で確認した。SenseVoice は CJK 特化の
#     CTC モデルで桁違いに速く、これらの問題がない
#   - 出力は type モード（wtype による Wayland virtual-keyboard 直接入力）。
#     日本語を含む任意のユニコードをそのままタイプでき、クリップボードを
#     汚さない。COSMIC 1.5 で動作することを実機確認済み（過去のバージョン
#     では誤動作報告があった）。フォールバックは dotool → クリップボード
#
# 初回セットアップ（ホストごとに1回、~/.local/share/voxtype/ へ取得）:
#   voxtype setup model        # SenseVoice モデル（対話選択）
#   voxtype setup vad          # silero VAD モデル（約2MB）
# =============================================================================
{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  hostName = osConfig.networking.hostName;

  # x1ng1 (4コア Tiger Lake) では large-v3-turbo の CPU 推論が遅すぎるため
  # small に落とす。認識精度は下がるが応答時間を優先する
  whisperModel = if hostName == "x1ng1" then "small" else "large-v3-turbo";

  # 推論スレッド数（whisper・SenseVoice 共用）。whisper.cpp のデフォルトは
  # 4 スレッドで実用にならない遅さだった（r995 で 13 秒の音声に 4 分超を実測）。
  # 物理コア数に合わせて並列化する
  cpuThreads =
    {
      r995 = 16; # Ryzen 9950X: 16C/32T
      t14g4 = 8; # Core i7-1355U: 2P+8E
      x1ng1 = 4; # Core i7-1160G7: 4C/8T
    }
    .${hostName} or 4;
in
{
  # SenseVoice 等の ONNX エンジンを含むバリアント。
  # 依存ツールの追加インストールは不要: nixpkgs の voxtype は wrapProgram で
  # dotool / wl-clipboard / wtype（および X11 用の xclip / xdotool）を
  # 自身の PATH に注入している
  home.packages = [ pkgs.voxtype-onnx ];

  # ===========================================================================
  # voxtype 設定
  # ===========================================================================
  # 注意: voxtype はセクションの部分省略を許さない（missing field でパース
  # エラーになる）ため、同梱 default-config.toml の全セクションを明示する
  xdg.configFile."voxtype/config.toml".text = ''
    # `voxtype record toggle` と `voxtype status` に必須
    state_file = "auto"

    # SenseVoice: CJK 特化の高速 CTC エンジン（ja/zh/ko/en/yue、ONNX）。
    # whisper はフォールバック用に [whisper] セクションを残してある
    # （`voxtype --engine whisper daemon` で切替可能）
    engine = "sensevoice"

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
    threads = ${toString cpuThreads}
    # context_window_optimization は有効化しない: 高速化はするが、turbo で
    # 既知の繰り返しループ（同一フレーズ連発）が実音声でも再現したため
    # 録音開始時にモデルをロードし、文字起こし後に解放する。
    # 常駐 RAM（large-v3-turbo で約 2GB）を節約する代わりに、
    # 使用のたびにロード時間（SSD なら 1〜2 秒）が加算される
    on_demand_loading = true

    [sensevoice]
    model = "sensevoice-small"
    language = "ja"
    # 句読点の自動付与
    use_itn = true
    threads = ${toString cpuThreads}
    # モデルが小さい（数百MB・ロード数百ms）ため常駐させ、応答を最速にする
    on_demand_loading = false

    [vad]
    # 音声区間検出。無音だけの録音を文字起こし前に棄却する。
    # 無音を whisper に通すと幻覚（「ご視聴ありがとうございました」等）を
    # 出力した上、デコードが数分間ループして CPU に張り付くため必須。
    # silero VAD モデル（約2MB）が必要: `voxtype setup vad` で取得する
    enabled = true
    backend = "whisper"

    [output]
    # wtype（Wayland virtual-keyboard）でカーソル位置に直接タイプする。
    # 日本語を含む任意のユニコードを入力でき、クリップボードを汚さない。
    # COSMIC 1.5 での動作は実機確認済み。
    # paste モード（クリップボード + ペーストキー打鍵）は不採用: Ctrl+V は
    # ターミナルで通用せず、Shift+Insert は Alacritty がプライマリ
    # セレクションを貼るため、アプリを問わず確実なペーストキーが存在しない
    mode = "type"
    driver_order = ["wtype", "dotool", "clipboard"]
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
        (modifiers: [Super], key: "v"): Spawn("${lib.getExe pkgs.voxtype-onnx} record toggle"),
        (modifiers: [Super, Shift], key: "v"): Spawn("${lib.getExe pkgs.kikitori}"),
    }
  '';

  # ===========================================================================
  # kikitori（voxtype 後継、試行中）
  # ===========================================================================
  # リアルタイム部分表示つきのローカル音声入力。Super+Shift+V で
  # 1 回目 = 録音開始（画面下部にバー表示）、2 回目 = 停止して wtype 入力。
  # エンジン kikitorid は r995 でのみ常駐し（初回起動時に ExecStartPre が
  # モデルを ~/.local/share/kikitori/ へ自動取得）、他ホストは
  # KIKITORI_ENGINE 経由で r995 へリモート接続する（下記）。
  # 安定を確認したら Super+V を kikitori に差し替え、voxtype を撤去する。
  # 置換辞書: ~/.config/kikitori/replace.tsv（任意）
  #
  # エンジン配置: r995 だけがエンジンを持ち、tailscale0 に TCP 公開する
  # （decode は常にエンジン側で走るため、非力なラップトップは薄い
  # クライアントに徹する。認証は tailnet の信頼モデルに委ねる）。
  # ラップトップが tailnet 外にいる間は音声入力不可（明示エラー）
  services.kikitori = {
    enable = hostName == "r995";
    tcp = if hostName == "r995" then "0.0.0.0:41717" else null;
  };
  home.sessionVariables = lib.mkIf (hostName != "r995") {
    KIKITORI_ENGINE = "r995:41717";
  };

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
      ExecStart = "${lib.getExe pkgs.voxtype-onnx} daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
