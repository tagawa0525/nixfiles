// =============================================================================
// zellij-slots: スロット式タブ管理プラグイン
// =============================================================================
// Zellij のタブは位置ベースで、閉じると後続が詰められ固定番号を持てない。
// そこでタブ「名」をスロット番号として扱い、tmux の window 番号運用を再現する:
//   - new:    優先順位で空いているスロット番号を名前にしてタブを作成
//   - goto:N: その名前のタブへフォーカス（不在なら何もしない）
// キーバインドの MessagePlugin から name="slots" のパイプで呼び出される。
// =============================================================================
// ホスト向けビルド（cargo test）ではプラグイン本体を除外するため、
// 未使用importと未使用定義の警告をwasm外でだけ抑制する
#![cfg_attr(not(target_arch = "wasm32"), allow(unused_imports, dead_code))]

use std::collections::{BTreeMap, HashMap};

use zellij_tile::prelude::*;

/// スロット番号の優先順位（押しやすい順）。tmux.nix の windowPriority と同じ
const SLOT_PRIORITY: [&str; 10] = ["3", "4", "2", "8", "7", "9", "5", "6", "1", "0"];

/// パイプの名前。キーバインド側の MessagePlugin と一致させる
const PIPE_NAME: &str = "slots";

/// タブラベルに表示するタイトルの最大文字数
const TITLE_MAX: usize = 15;

/// 優先順位で最初に空いているスロット番号を返す。全て使用中なら None
fn find_free_slot(used: &[String]) -> Option<&'static str> {
    SLOT_PRIORITY
        .iter()
        .copied()
        .find(|slot| !used.iter().any(|name| name == slot))
}

/// タブ名がスロット番号（1桁の数字）ならその値を返す
fn slot_of(name: &str) -> Option<u32> {
    if name.len() == 1 && SLOT_PRIORITY.contains(&name) {
        name.parse().ok()
    } else {
        None
    }
}

/// ステータスバーの表示順を返す（引数は (position, name) の列）。
/// tmuxのwindow一覧と同様、スロット番号の昇順で並べる。作成順（position）
/// とは無関係に番号と指の位置を一致させるため。スロット外の名前のタブは
/// 末尾にposition順で置く
fn display_order(tabs: &[(usize, String)]) -> Vec<usize> {
    let mut order: Vec<&(usize, String)> = tabs.iter().collect();
    // スロットは (0, 番号)、スロット外は (1, position) をキーに安定ソート
    order.sort_by_key(|(position, name)| match slot_of(name) {
        Some(slot) => (0, slot as usize),
        None => (1, *position),
    });
    order.into_iter().map(|(position, _)| *position).collect()
}

/// タブ1つ分の表示ラベルを作る。tmuxの「#I:#W」相当で「3:fish」の形式。
/// タイトルは長すぎるとバーを圧迫するので TITLE_MAX 文字で切り詰める
fn tab_label(name: &str, title: &str) -> String {
    if slot_of(name).is_none() || title.is_empty() {
        return name.to_string();
    }
    let short: String = title.chars().take(TITLE_MAX).collect();
    format!("{}:{}", name, short)
}

/// エポック秒を日本時間の「%Y/%m/%d %H:%M」に整形する（tmuxのstatus-right相当。
/// 日本にDSTはないので固定+9時間で足りる）
fn format_datetime_jst(epoch_secs: u64) -> String {
    let jst = epoch_secs + 9 * 3600;
    let (days, secs) = (jst / 86400, jst % 86400);
    // civil-from-days（Howard Hinnantのアルゴリズム）
    let z = days as i64 + 719_468;
    let era = z / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { year + 1 } else { year };
    format!(
        "{:04}/{:02}/{:02} {:02}:{:02}",
        year,
        month,
        day,
        secs / 3600,
        (secs % 3600) / 60
    )
}

/// 次の分の頭までの秒数（時計表示の更新タイマー用）
fn secs_to_next_minute(epoch_secs: u64) -> f64 {
    (60 - epoch_secs % 60) as f64
}

/// バー左側のクリック領域を組み立てる（(ラベル, switch_tab_to用index) の列から）。
/// マウスイベントの列は端末のセル列なので、文字数ではなくセル幅で数える。
/// 文字数で数えると全角文字（日本語のタイトル等）でクリック位置がずれる
fn build_click_regions(prefix: &str, labels: &[(String, u32)]) -> Vec<(usize, usize, u32)> {
    let mut col = cell_width(prefix);
    labels
        .iter()
        .map(|(label, idx)| {
            let start = col;
            col += cell_width(label);
            (start, col, *idx)
        })
        .collect()
}

/// 文字列の端末上のセル幅（全角は2セル）
fn cell_width(s: &str) -> usize {
    unicode_width::UnicodeWidthStr::width(s)
}

// =============================================================================
// 役割の分離
// =============================================================================
// このwasmは設定によって2つの役割で動く:
// - bar:   レイアウトからタブごとにインスタンス化され、ステータスバーを描画する。
//          隠れているタブのインスタンスにはイベントが届かず状態が古くなるため、
//          パイプの処理はしない（古い状態で空きスロットを計算すると、1回の
//          prefix+cで複数タブができる・空き番号を再利用しないなどの不整合が
//          起きることを実測で確認済み）
// - actor: キーバインドのMessagePlugin（設定なし）が最初のパイプで起動する
//          バックグラウンドのシングルトン。パイプ（new/goto）を一手に担う。
//          Zellijのパイプは (URL, 設定) が一致するインスタンスへ配送されるため、
//          barと設定を分けることで唯一の宛先になる
#[derive(Default)]
struct State {
    is_bar: bool,
    tabs: Vec<TabInfo>,
    panes: HashMap<usize, Vec<PaneInfo>>,
    mode_info: ModeInfo,
    /// actor: 初回のTabUpdateを受け取るまでtabsは空で信用できない。
    /// その間に来た new は積んでおき、状態が届いてから処理する
    got_tab_state: bool,
    queued_news: usize,
    /// actor: 作成したがまだTabUpdateに現れていないスロット。
    /// 直前の作成が反映される前に次のnewが来ても同じ番号を選ばないための帳簿
    pending_created: Vec<String>,
    /// bar: 直近のrenderで確定したクリック領域: [start, end) 表示列 → switch_tab_to用の1-based index
    click_regions: Vec<(usize, usize, u32)>,
}

// Zellijのホスト関数はwasm実行環境にしか存在せず、ホスト向けの
// cargo test ではリンクできないため、プラグイン本体はwasm限定にする
#[cfg(target_arch = "wasm32")]
register_plugin!(State);

// ユニットテスト実行時のバイナリビルドを通すためのダミー
#[cfg(not(target_arch = "wasm32"))]
fn main() {}

#[cfg(target_arch = "wasm32")]
fn now_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

/// 「title:<pane_id>:<コマンド名>」形式のパイプペイロードを解析する。
/// fishのフック（fish_preexec / fish_prompt）がコマンドの開始・終了を
/// このペイロードで通知してくる（Zellijはペインタイトルの変更だけでは
/// イベントを発行しないため、シェル側から押し込む必要がある）
fn parse_title_payload(payload: &str) -> Option<(u32, &str)> {
    let _ = payload;
    todo!()
}

/// タブに表示するタイトル（tmuxの#W相当）。フォーカス中のペインを優先し、
/// 自分自身を含むプラグインペイン（ステータスバー）は除外する。
/// overrides（fishフック由来のペインID→コマンド名）があればそちらを優先する
/// （PaneInfo.titleは構造変化時にしか更新されず古いため）
fn title_for_tab(panes: Option<&Vec<PaneInfo>>, overrides: &HashMap<u32, String>) -> String {
    let _ = (panes, overrides);
    todo!()
}

#[cfg(target_arch = "wasm32")]
impl State {
    /// 優先順位の空きスロットに新規タブを作る（tmuxのnew-window相当）。
    /// 直前の作成がTabUpdateに反映される前に次のnewが来ても同じ番号を
    /// 選ばないよう、pending_createdを合算して空きを計算する。
    /// 全スロット使用中は何もしない（10タブが上限）
    fn create_slot_tab(&mut self) {
        let mut used: Vec<String> = self.tabs.iter().map(|t| t.name.clone()).collect();
        used.extend(self.pending_created.iter().cloned());
        if let Some(slot) = find_free_slot(&used) {
            focus_or_create_tab(slot);
            self.pending_created.push(slot.to_string());
        }
    }
}

#[cfg(target_arch = "wasm32")]
impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        self.is_bar = configuration.get("role").map(String::as_str) == Some("bar");
        if self.is_bar {
            set_selectable(false);
            subscribe(&[
                EventType::TabUpdate,
                EventType::PaneUpdate,
                EventType::ModeUpdate,
                EventType::Timer,
                EventType::Mouse,
            ]);
            // 時計の更新タイマー。初回発火時に分頭へ揃える
            set_timeout(1.0);
        } else {
            subscribe(&[EventType::TabUpdate]);
            // パイプ起動でフローティングペインが付いた場合に備えて隠す
            hide_self();
        }
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
                self.got_tab_state = true;
                // 作成がタブ一覧に反映されたらpendingから外す
                self.pending_created
                    .retain(|slot| !self.tabs.iter().any(|t| &t.name == slot));
                // 起動直後（状態が届く前）に受けた new をここで処理する
                while self.queued_news > 0 {
                    self.queued_news -= 1;
                    self.create_slot_tab();
                }
                true
            }
            Event::PaneUpdate(manifest) => {
                self.panes = manifest.panes;
                true
            }
            Event::ModeUpdate(mode_info) => {
                self.mode_info = mode_info;
                true
            }
            Event::Timer(_) => {
                set_timeout(secs_to_next_minute(now_epoch()));
                true
            }
            Event::Mouse(Mouse::LeftClick(_, col)) => {
                let hit = self
                    .click_regions
                    .iter()
                    .find(|(start, end, _)| (*start..*end).contains(&col));
                if let Some((_, _, idx)) = hit {
                    switch_tab_to(*idx);
                }
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        // パイプはactorだけが処理する（barは状態が古くなり得るため）
        if self.is_bar || message.name != PIPE_NAME {
            return false;
        }
        match message.payload.as_deref() {
            Some("new") => {
                if self.got_tab_state {
                    self.create_slot_tab();
                } else {
                    // 起動直後でタブ状態が届いていない。空のused（=スロット3が
                    // 空きに見える）で計算すると既存タブへのフォーカスに化ける
                    // ため、TabUpdate後に処理する
                    self.queued_news += 1;
                }
            }
            Some(payload) => {
                if let Some(slot) = payload.strip_prefix("goto:") {
                    go_to_tab_name(slot);
                }
            }
            None => {}
        }
        false
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        // 左側: セッション名 + スロット番号順のタブ一覧（tmuxのstatus-left + window一覧相当）
        let session = self.mode_info.session_name.clone().unwrap_or_default();
        let prefix = format!("{} | ", session);
        let mut ansi = prefix.clone();
        let positions: Vec<(usize, String)> = self
            .tabs
            .iter()
            .map(|t| (t.position, t.name.clone()))
            .collect();
        let mut labels: Vec<(String, u32)> = Vec::new();
        for position in display_order(&positions) {
            let Some(tab) = self.tabs.iter().find(|t| t.position == position) else {
                continue;
            };
            let title = title_for_tab(self.panes.get(&position));
            let label = format!(" {} ", tab_label(&tab.name, &title));
            if tab.active {
                // tmuxのwindow-status-current-style bg=white に合わせる
                ansi.push_str(&format!("\u{1b}[47;30m{}\u{1b}[0m", label));
            } else {
                ansi.push_str(&label);
            }
            labels.push((label, position as u32 + 1));
        }
        self.click_regions = build_click_regions(&prefix, &labels);
        let left_width =
            cell_width(&prefix) + labels.iter().map(|(l, _)| cell_width(l)).sum::<usize>();

        // 右側: モード表示 + 日時（tmuxのstatus-right相当）
        let marker = match self.mode_info.mode {
            InputMode::Tmux => " ^\\ ",
            InputMode::Scroll => " SCROLL ",
            InputMode::EnterSearch | InputMode::Search => " SEARCH ",
            InputMode::RenameTab => " RENAME ",
            _ => "",
        };
        let datetime = format_datetime_jst(now_epoch());
        let right_plain = format!("{}{}", marker, datetime);
        let right_ansi = if marker.is_empty() {
            datetime.clone()
        } else {
            format!("\u{1b}[43;30m{}\u{1b}[0m{}", marker, datetime)
        };

        let used = left_width + cell_width(&right_plain);
        print!(
            "{}{}{}",
            ansi,
            " ".repeat(cols.saturating_sub(used)),
            right_ansi
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn 空のとき最優先の3を返す() {
        assert_eq!(find_free_slot(&[]), Some("3"));
    }

    #[test]
    fn 優先順位どおりに次の空きを返す() {
        assert_eq!(find_free_slot(&names(&["3"])), Some("4"));
        assert_eq!(find_free_slot(&names(&["3", "4"])), Some("2"));
        assert_eq!(find_free_slot(&names(&["3", "4", "2"])), Some("8"));
    }

    #[test]
    fn 途中の空きスロットを再利用する() {
        // 3,4,2,8 から 4 を閉じた状態
        assert_eq!(find_free_slot(&names(&["3", "2", "8"])), Some("4"));
    }

    #[test]
    fn スロット外の名前は使用状況に影響しない() {
        // 手動リネームされたタブがあっても空き判定は変わらない
        assert_eq!(find_free_slot(&names(&["3", "logs"])), Some("4"));
    }

    #[test]
    fn 全スロット使用中はnoneを返す() {
        let all: Vec<String> = SLOT_PRIORITY.iter().map(|s| s.to_string()).collect();
        assert_eq!(find_free_slot(&all), None);
    }

    #[test]
    fn スロット番号の判定() {
        assert_eq!(slot_of("3"), Some(3));
        assert_eq!(slot_of("0"), Some(0));
        assert_eq!(slot_of("logs"), None);
        assert_eq!(slot_of(""), None);
        // 2桁はスロット外（優先順位は1桁のみ）
        assert_eq!(slot_of("10"), None);
    }

    fn tabs(v: &[(usize, &str)]) -> Vec<(usize, String)> {
        v.iter().map(|(p, n)| (*p, n.to_string())).collect()
    }

    #[test]
    fn 表示順は作成順ではなくスロット番号の昇順() {
        // 作成順 3 → 4 → 2 → 8 でも表示は 2 3 4 8
        let t = tabs(&[(0, "3"), (1, "4"), (2, "2"), (3, "8")]);
        assert_eq!(display_order(&t), vec![2, 0, 1, 3]);
    }

    #[test]
    fn スロット外の名前は末尾にposition順で並ぶ() {
        let t = tabs(&[(0, "logs"), (1, "3"), (2, "build"), (3, "2")]);
        assert_eq!(display_order(&t), vec![3, 1, 0, 2]);
    }

    #[test]
    fn ラベルはスロットとタイトルをコロンで繋ぐ() {
        assert_eq!(tab_label("3", "fish"), "3:fish");
        // タイトルが空ならスロット番号だけ
        assert_eq!(tab_label("3", ""), "3");
        // スロット外の名前はそのまま（タイトルは付けない）
        assert_eq!(tab_label("logs", "fish"), "logs");
    }

    #[test]
    fn ラベルのタイトルは切り詰められる() {
        let long = "very-long-command-name-here";
        let label = tab_label("3", long);
        assert_eq!(label, format!("3:{}", &long[..TITLE_MAX]));
    }

    #[test]
    fn 日時は日本時間で整形される() {
        // 2026-08-05T17:30:00Z = JST 2026-08-06 02:30
        assert_eq!(format_datetime_jst(1785951000), "2026/08/06 02:30");
        // うるう年: 2024-02-28T15:30:00Z = JST 2024-02-29 00:30
        assert_eq!(format_datetime_jst(1709134200), "2024/02/29 00:30");
        // 年末年始のUTC跨ぎ: 2025-12-31T20:01:00Z = JST 2026-01-01 05:01
        assert_eq!(format_datetime_jst(1767211260), "2026/01/01 05:01");
    }

    #[test]
    fn 次の分までの秒数() {
        assert_eq!(secs_to_next_minute(120), 60.0); // ちょうど分頭なら次の分まで60秒
        assert_eq!(secs_to_next_minute(121), 59.0);
        assert_eq!(secs_to_next_minute(179), 1.0);
    }

    fn labels(v: &[(&str, u32)]) -> Vec<(String, u32)> {
        v.iter().map(|(s, i)| (s.to_string(), *i)).collect()
    }

    #[test]
    fn クリック領域はセル幅で数える() {
        // ASCIIのみ: "main | " = 7セル
        assert_eq!(
            build_click_regions("main | ", &labels(&[(" 2:a ", 3), (" 3:b ", 1)])),
            vec![(7, 12, 3), (12, 17, 1)]
        );
    }

    #[test]
    fn タイトルペイロードを解析できる() {
        assert_eq!(parse_title_payload("title:3:vim"), Some((3, "vim")));
        // コマンド名にコロンが含まれても最初の区切りだけで分割する
        assert_eq!(parse_title_payload("title:12:a:b"), Some((12, "a:b")));
        assert_eq!(parse_title_payload("title:x:vim"), None);
        assert_eq!(parse_title_payload("title:3"), None);
        assert_eq!(parse_title_payload("new"), None);
    }

    #[test]
    fn タイトルはフック由来を優先しペイン情報にフォールバックする() {
        let pane = |id: u32, focused: bool, title: &str| PaneInfo {
            id,
            is_focused: focused,
            title: title.to_string(),
            ..Default::default()
        };
        let plugin_pane = |id: u32| PaneInfo {
            id,
            is_plugin: true,
            title: "bar".to_string(),
            ..Default::default()
        };
        let panes = vec![
            plugin_pane(9),
            pane(1, false, "old-title"),
            pane(2, true, "osc-title"),
        ];
        let mut overrides: HashMap<u32, String> = HashMap::new();

        // フック未通知: フォーカス中の端末ペインのタイトル（プラグインペインは除外）
        assert_eq!(title_for_tab(Some(&panes), &overrides), "osc-title");
        // フック通知あり: そのペインの上書きタイトルを優先
        overrides.insert(2, "vim".to_string());
        assert_eq!(title_for_tab(Some(&panes), &overrides), "vim");
        // 別ペインの上書きは影響しない
        overrides.clear();
        overrides.insert(1, "other".to_string());
        assert_eq!(title_for_tab(Some(&panes), &overrides), "osc-title");
        // ペイン情報なし
        assert_eq!(title_for_tab(None, &overrides), "");
    }

    #[test]
    fn 全角文字は2セルとして数える() {
        // " 3:日本語 " = 1+2+2*3+1 = 10セル（文字数は7）
        assert_eq!(
            build_click_regions("m | ", &labels(&[(" 3:日本語 ", 1), (" 4:x ", 2)])),
            vec![(4, 14, 1), (14, 19, 2)]
        );
        assert_eq!(cell_width("あa"), 3);
    }
}
