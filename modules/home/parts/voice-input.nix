# =============================================================================
# 音声入力 (kikitori + SenseVoice)
# =============================================================================
# OS 全体（任意のアプリ）で使えるローカル音声入力。
# https://github.com/tagawa0525/kikitori
#
# 仕組み:
#   - エンジン kikitorid が r995 に常駐し、SenseVoice（ONNX、完全ローカル、
#     日本語対応）で逐次文字起こしする
#   - COSMIC のカスタムショートカット Super+V で、1 回目 = 録音開始
#     （画面中央にバー表示、部分認識をリアルタイム更新）、
#     2 回目 = 停止して確定テキストを wtype でカーソル位置に入力
#
# 設計上の選択（voxtype 時代からの検証結果を含む）:
#   - ホットキーは kikitori 内蔵の evdev 監視ではなく COSMIC キーバインドで
#     制御する。evdev 監視は input グループ加入（= 全キーボードの生イベント
#     読み取り権限）が必要で、openlogi.nix で意図的に避けているキーロガー面を
#     開いてしまうため
#   - エンジンは whisper ではなく SenseVoice。whisper large-v3-turbo は
#     r995(16スレッド) でも数秒の発話に 8〜10 秒かかり、繰り返し幻覚
#     （同一フレーズの連発）も実音声で確認した。SenseVoice は CJK 特化の
#     CTC モデルで桁違いに速く、これらの問題がない
#   - 出力は wtype による Wayland virtual-keyboard 直接入力。日本語を含む
#     任意のユニコードをそのままタイプでき、クリップボードを汚さない。
#     paste モード（クリップボード + ペーストキー打鍵）は不採用: Ctrl+V は
#     ターミナルで通用せず、Shift+Insert は Alacritty がプライマリ
#     セレクションを貼るため、アプリを問わず確実なペーストキーが存在しない
#   - 無音区間の棄却に silero VAD を使う。無音を推論に通すと幻覚
#     （「ご視聴ありがとうございました」等）が出る
#
# 経緯: 前身は voxtype (https://github.com/peteonrails/voxtype)。逐次表示を
# 得るために kikitori を自作し、2026-08-02 に Super+V を kikitori へ移した。
# フォールバックとして Super+Shift+V に残していた voxtype は 2026-08-05 に
# 撤去した（同じ SenseVoice モデルを二重に常駐ロードして約 1GB を占めていた）
# =============================================================================
{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  hostName = osConfig.networking.hostName;

  # kikitori のエンジン接続先。r995 は自ホストの kikitorid（Unix ソケット、
  # クライアント側の既定値）を使うため指定不要
  kikitoriEngine = if hostName == "r995" then null else "r995:41717";

  # COSMIC のショートカットが起動する kikitori コマンド。
  # エンジン接続先は環境変数 KIKITORI_ENGINE ではなく引数で明示する:
  # Spawn は cosmic-comp の環境を継承するが、cosmic-comp は
  # cosmic-greeter/cosmic-session 経由で起動されるためログインシェルを通らず、
  # home.sessionVariables（profile.d 経由）が届かない。届かないまま起動した
  # クライアントはローカルソケットに接続を試みて失敗し、バーを出さないまま
  # プロセスだけが残る（接続失敗時に exit しない upstream の挙動）。
  # --socket は "host:port" 形式を TCP として解釈する
  kikitoriCommand =
    lib.getExe pkgs.kikitori
    + lib.optionalString (kikitoriEngine != null) " --socket ${kikitoriEngine}";
in
{
  # ===========================================================================
  # COSMIC カスタムショートカット
  # ===========================================================================
  xdg.configFile."cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom".text = ''
    {
        (modifiers: [Super], key: "v"): Spawn("${kikitoriCommand}"),
    }
  '';

  # ===========================================================================
  # kikitori
  # ===========================================================================
  # エンジン kikitorid は r995 でのみ常駐し（初回起動時に ExecStartPre が
  # モデルを ~/.local/share/kikitori/ へ自動取得）、他ホストは
  # --socket 引数で r995 へリモート接続する（上記 kikitoriCommand）。
  # 置換辞書: ~/.config/kikitori/replace.tsv（任意）
  #
  # エンジン配置: r995 だけがエンジンを持ち、tailscale0 に TCP 公開する
  # （decode は常にエンジン側で走るため、非力なラップトップは薄い
  # クライアントに徹する。認証は tailnet の信頼モデルに委ねる）。
  # ラップトップが tailnet 外にいる間は音声入力不可（クライアントは接続に
  # 失敗するとバーを出さずに待機し続けるため、無反応に見える）
  services.kikitori = {
    enable = hostName == "r995";
    tcp = if hostName == "r995" then "0.0.0.0:41717" else null;
  };
  # 対話シェルから kikitori-cli を直接叩くとき用。COSMIC の Super+V は
  # この変数に依存しない（上記 kikitoriCommand の理由を参照）
  home.sessionVariables = lib.mkIf (kikitoriEngine != null) {
    KIKITORI_ENGINE = kikitoriEngine;
  };
}
