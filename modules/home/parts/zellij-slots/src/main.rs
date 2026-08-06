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

#[derive(Default)]
struct State {
    tabs: Vec<TabInfo>,
    panes: HashMap<usize, Vec<PaneInfo>>,
    mode_info: ModeInfo,
    /// 直近のrenderで確定したクリック領域: [start, end) 表示列 → switch_tab_to用の1-based index
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

/// タブに表示するタイトル（tmuxの#W相当）。フォーカス中のペインを優先し、
/// 自分自身を含むプラグインペイン（ステータスバー）は除外する
#[cfg(target_arch = "wasm32")]
fn title_for_tab(panes: Option<&Vec<PaneInfo>>) -> String {
    let Some(panes) = panes else {
        return String::new();
    };
    let terminals: Vec<&PaneInfo> = panes.iter().filter(|p| !p.is_plugin).collect();
    terminals
        .iter()
        .find(|p| p.is_focused)
        .or_else(|| terminals.first())
        .map(|p| p.title.clone())
        .unwrap_or_default()
}

#[cfg(target_arch = "wasm32")]
impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
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
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
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
        if message.name != PIPE_NAME {
            return false;
        }
        let tab_names: Vec<String> = self.tabs.iter().map(|t| t.name.clone()).collect();
        match message.payload.as_deref() {
            Some("new") => {
                // このプラグインはタブごとにインスタンス化され、パイプは
                // 全インスタンスに配送される。new_tab だと1回の操作で
                // インスタンス数だけタブが並ぶため、冪等な
                // focus_or_create_tab を使う（最初の1つが作成、残りはフォーカス）。
                // 全スロット使用中は何もしない（10タブが上限）
                if let Some(slot) = find_free_slot(&tab_names) {
                    focus_or_create_tab(slot);
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
        let mut plain = format!("{} | ", session);
        let mut ansi = plain.clone();
        self.click_regions.clear();
        let positions: Vec<(usize, String)> = self
            .tabs
            .iter()
            .map(|t| (t.position, t.name.clone()))
            .collect();
        for position in display_order(&positions) {
            let Some(tab) = self.tabs.iter().find(|t| t.position == position) else {
                continue;
            };
            let title = title_for_tab(self.panes.get(&position));
            let label = format!(" {} ", tab_label(&tab.name, &title));
            let start = plain.chars().count();
            plain.push_str(&label);
            self.click_regions
                .push((start, plain.chars().count(), position as u32 + 1));
            if tab.active {
                // tmuxのwindow-status-current-style bg=white に合わせる
                ansi.push_str(&format!("\u{1b}[47;30m{}\u{1b}[0m", label));
            } else {
                ansi.push_str(&label);
            }
        }

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

        let used = plain.chars().count() + right_plain.chars().count();
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
}
