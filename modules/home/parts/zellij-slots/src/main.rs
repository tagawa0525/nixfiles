// =============================================================================
// zellij-slots: スロット式タブ管理プラグイン
// =============================================================================
// Zellij のタブは位置ベースで、閉じると後続が詰められ固定番号を持てない。
// そこでタブ「名」をスロット番号として扱い、tmux の window 番号運用を再現する:
//   - 作成:   キーバインドの標準アクション NewTab が作った「Tab #N」名のタブを
//             検出し、優先順位で空いているスロット番号にリネームする
//   - goto:N: その名前のタブへフォーカス（不在なら何もしない）。
//             キーバインドの MessagePlugin から name="slots" のパイプで届く
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

/// 標準アクションNewTabが付けるデフォルト名（"Tab #N"）ならtrue
fn is_default_tab_name(name: &str) -> bool {
    name.strip_prefix("Tab #")
        .is_some_and(|rest| !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()))
}

/// デフォルト名のタブへのスロット割り当てを決める（(position, スロット名) の列）。
/// スロットの空きはデフォルト名以外の全タブ名を使用中として計算し、
/// 複数あればposition順に割り当てる。空きがなければ割り当てない
/// （デフォルト名のまま残り、バーには末尾に表示される）
fn assign_slots(tabs: &[(usize, String)]) -> Vec<(usize, &'static str)> {
    let mut used: Vec<String> = tabs
        .iter()
        .filter(|(_, name)| !is_default_tab_name(name))
        .map(|(_, name)| name.clone())
        .collect();
    let mut out = Vec::new();
    for (position, name) in tabs {
        if !is_default_tab_name(name) {
            continue;
        }
        let Some(slot) = find_free_slot(&used) else {
            break;
        };
        used.push(slot.to_string());
        out.push((*position, slot));
    }
    out
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

/// タブラベル列を利用可能なセル幅に収める。
/// 溢れる場合はタイトルを均等予算で切り詰め、スロット番号は常に全て表示する
/// （番号が指の位置と対応するのがこのバーの主目的のため）。
/// 入力は (タブ名, タイトル)、出力は前後に空白を含む表示ラベル
fn fit_labels(tabs: &[(String, String)], available: usize) -> Vec<String> {
    let full: Vec<String> = tabs
        .iter()
        .map(|(name, title)| format!(" {} ", tab_label(name, title)))
        .collect();
    if full.iter().map(|l| cell_width(l)).sum::<usize>() <= available {
        return full;
    }
    // タイトル付きラベルの固定部（" 名前 " とコロン）を除いた残りを
    // タイトルの予算として均等に割り当てる
    let has_title = |name: &str, title: &str| slot_of(name).is_some() && !title.is_empty();
    let titled = tabs.iter().filter(|(n, t)| has_title(n, t)).count();
    let fixed: usize = tabs
        .iter()
        .map(|(n, t)| cell_width(&format!(" {} ", n)) + usize::from(has_title(n, t)))
        .sum();
    let budget = if titled > 0 {
        available.saturating_sub(fixed) / titled
    } else {
        0
    };
    tabs.iter()
        .map(|(name, title)| {
            if !has_title(name, title) || budget == 0 {
                return format!(" {} ", name);
            }
            let mut used = 0;
            let short: String = title
                .chars()
                .take_while(|c| {
                    used += unicode_width::UnicodeWidthChar::width(*c).unwrap_or(0);
                    used <= budget
                })
                .collect();
            if short.is_empty() {
                format!(" {} ", name)
            } else {
                format!(" {}:{} ", name, short)
            }
        })
        .collect()
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
// クライアント独立の設計
// =============================================================================
// このwasmはレイアウトからタブごと・クライアントごとにインスタンス化され、
// ステータスバーを描画する。多重アタッチでは各クライアントが独立に動くべき
// （旧tmuxのグループセッション相当）だが、プラグインAPI経由のフォーカス操作は
// どのクライアント名義で実行されるかが不定という制約がある（実測。Zellij側に
// クライアントを指定する手段がない）。そこで:
// - タブ作成はプラグインを使わず、キーバインドの標準アクションNewTabで行う
//   （標準アクションは押した本人のクライアントだけを動かす）。プラグインは
//   「Tab #N」名で生まれたタブを空きスロット名にリネームするだけ。リネームは
//   フォーカスを動かさない操作なのでクライアント帰属問題と無縁
// - タブ移動（goto）はパイプで全インスタンスに届く。実行するのは
//   「自分のクライアントのlocked→tmux遷移（=prefix押下）を観測し（armed）、
//   かつ自分のタブがいま表示されている」インスタンスだけ。モードは
//   クライアントごとに独立しているのでこれで押した本人に絞れる。
//   モードの「値」ではなく「遷移」を見るのは、prefix押下中に生まれた
//   新しいタブのバーは初期モードがtmuxのまま届き、隠れたバーはイベントが
//   止まってtmuxのまま凍結するため。値だけで判定すると、そうした
//   インスタンスが他クライアントの操作に反応してしまう（実測）
#[derive(Default)]
struct State {
    tabs: Vec<TabInfo>,
    panes: HashMap<usize, Vec<PaneInfo>>,
    mode_info: ModeInfo,
    /// ModeUpdateを一度でも受け取ったか（初回はlocked→tmuxの遷移判定に使えない）
    got_mode: bool,
    /// 自分のクライアントの「locked→tmuxの遷移」（=prefix押下）を観測済みか。
    /// goto実行後・tmux以外への遷移で解除する（詳細は上の設計コメント）
    prefix_armed: bool,
    /// 直近のrenderで確定したクリック領域: [start, end) 表示列 → switch_tab_to用の1-based index
    click_regions: Vec<(usize, usize, u32)>,
    /// fishフック由来のペインID→実行中コマンド名（PaneInfo.titleより優先）
    titles: HashMap<u32, String>,
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
    let rest = payload.strip_prefix("title:")?;
    let (pane_id, title) = rest.split_once(':')?;
    Some((pane_id.parse().ok()?, title))
}

/// タブに表示するタイトル（tmuxの#W相当）。フォーカス中のペインを優先し、
/// 自分自身を含むプラグインペイン（ステータスバー）は除外する。
/// overrides（fishフック由来のペインID→コマンド名）があればそちらを優先する
/// （PaneInfo.titleは構造変化時にしか更新されず古いため）
fn title_for_tab(panes: Option<&Vec<PaneInfo>>, overrides: &HashMap<u32, String>) -> String {
    let Some(panes) = panes else {
        return String::new();
    };
    let terminals: Vec<&PaneInfo> = panes.iter().filter(|p| !p.is_plugin).collect();
    terminals
        .iter()
        .find(|p| p.is_focused)
        .or_else(|| terminals.first())
        .map(|p| {
            overrides
                .get(&p.id)
                .cloned()
                .unwrap_or_else(|| p.title.clone())
        })
        .unwrap_or_default()
}

#[cfg(target_arch = "wasm32")]
impl State {
    /// 自分の置かれたタブが、いま自分のクライアントに表示されているか。
    /// 自分のタブはイベントで届いたTabInfo.active（受け取った当人のタブが
    /// trueになる）から名前で覚え、ホストへの同期問い合わせと突き合わせる。
    /// positionはタブを閉じると詰まって古い値とずれるため、名前で比べる
    fn is_showing(&self) -> bool {
        let Some(own) = self.tabs.iter().find(|t| t.active) else {
            return false;
        };
        get_focused_pane_info()
            .ok()
            .and_then(|(tab_id, _)| get_tab_info(tab_id))
            .is_some_and(|showing| showing.name == own.name)
    }
}

#[cfg(target_arch = "wasm32")]
impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            // CLIパイプ（fishフックのtitle通知）の受信とunblockに必要
            PermissionType::ReadCliPipes,
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
                // 標準アクションNewTabで生まれた「Tab #N」名のタブに空きスロット
                // 名を付ける。イベントが届くのは表示中のインスタンスだけで、
                // どれも同じタブ一覧から同じ割り当てを計算するため、複数の
                // インスタンスが同時にリネームしても結果は変わらない（冪等）
                let positions: Vec<(usize, String)> = self
                    .tabs
                    .iter()
                    .map(|t| (t.position, t.name.clone()))
                    .collect();
                for (position, slot) in assign_slots(&positions) {
                    // rename_tabの位置は1-based（Zellij側でsaturating_sub(1)される）
                    rename_tab(position as u32 + 1, slot);
                }
                true
            }
            Event::PaneUpdate(manifest) => {
                self.panes = manifest.panes;
                // 閉じたペインの上書きタイトルを掃除する
                let live: std::collections::HashSet<u32> = self
                    .panes
                    .values()
                    .flatten()
                    .filter(|p| !p.is_plugin)
                    .map(|p| p.id)
                    .collect();
                self.titles.retain(|id, _| live.contains(id));
                true
            }
            Event::ModeUpdate(mode_info) => {
                let was = self.mode_info.mode;
                self.mode_info = mode_info;
                if self.mode_info.mode != InputMode::Tmux {
                    self.prefix_armed = false;
                } else if self.got_mode && was != InputMode::Tmux {
                    // 自分のクライアントがprefixを押した瞬間だけ武装する。
                    // 初回のModeUpdate（インスタンス生成時の現在値）は遷移では
                    // ないので対象外
                    self.prefix_armed = true;
                }
                self.got_mode = true;
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
        // CLI経由のパイプは、受信側がunblockしないと送信コマンドが
        // 終了せずブロックし続ける（fishフックのプロセスが溜まる）
        if let PipeSource::Cli(pipe_id) = &message.source {
            unblock_cli_pipe_input(pipe_id);
        }
        // title通知は描画に取り込む
        if let Some((pane_id, title)) = message.payload.as_deref().and_then(parse_title_payload) {
            self.titles.insert(pane_id, title.to_string());
            return true;
        }
        // タブ移動（goto）は全インスタンスに配送される。実行するのは
        // 押した本人のクライアントの、表示中のインスタンスだけ
        // （判定の根拠は上の「クライアント独立の設計」を参照）
        if !self.prefix_armed || !self.is_showing() {
            return false;
        }
        self.prefix_armed = false;
        if let Some(slot) = message
            .payload
            .as_deref()
            .and_then(|p| p.strip_prefix("goto:"))
        {
            go_to_tab_name(slot);
        }
        // lockedへの復帰はキーバインドではなくここで行う。キーバインドに
        // SwitchToModeを置くと、パイプが届く前にlockedへ戻ってしまい、
        // 上の判定が成立しなくなる。移動先が無いときも必ず戻す
        // （戻さないと以降のキーがすべてprefix扱いになる）
        switch_to_input_mode(&InputMode::Locked);
        false
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        // 右側: モード表示 + 日時（tmuxのstatus-right相当）。
        // 左側の幅予算を決めるため先に組み立てる
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

        // 左側: セッション名 + スロット番号順のタブ一覧（tmuxのstatus-left + window一覧相当）。
        // 端末幅を超えると1行ペインの表示が崩れるため、ラベルは幅予算に収める
        let session = self.mode_info.session_name.clone().unwrap_or_default();
        let prefix = format!("{} | ", session);
        let positions: Vec<(usize, String)> = self
            .tabs
            .iter()
            .map(|t| (t.position, t.name.clone()))
            .collect();
        let order = display_order(&positions);
        let name_titles: Vec<(String, String)> = order
            .iter()
            .filter_map(|position| {
                let tab = self.tabs.iter().find(|t| t.position == *position)?;
                let title = title_for_tab(self.panes.get(position), &self.titles);
                Some((tab.name.clone(), title))
            })
            .collect();
        let available = cols.saturating_sub(cell_width(&prefix) + cell_width(&right_plain));
        let fitted = fit_labels(&name_titles, available);

        let mut ansi = prefix.clone();
        let mut labels: Vec<(String, u32)> = Vec::new();
        for (position, label) in order.iter().zip(fitted) {
            let active = self
                .tabs
                .iter()
                .find(|t| t.position == *position)
                .is_some_and(|t| t.active);
            if active {
                // tmuxのwindow-status-current-style bg=white に合わせる
                ansi.push_str(&format!("\u{1b}[47;30m{}\u{1b}[0m", label));
            } else {
                ansi.push_str(&label);
            }
            labels.push((label, *position as u32 + 1));
        }
        self.click_regions = build_click_regions(&prefix, &labels);
        let left_width =
            cell_width(&prefix) + labels.iter().map(|(l, _)| cell_width(l)).sum::<usize>();

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
    fn デフォルトタブ名の判定() {
        assert!(is_default_tab_name("Tab #1"));
        assert!(is_default_tab_name("Tab #12"));
        assert!(!is_default_tab_name("3"));
        assert!(!is_default_tab_name("logs"));
        assert!(!is_default_tab_name("Tab #"));
        assert!(!is_default_tab_name("Tab #x"));
    }

    #[test]
    fn デフォルト名のタブに優先順位でスロットを割り当てる() {
        // 「3」使用中に NewTab で生まれた Tab #2 → 次の優先「4」
        let t = tabs(&[(0, "3"), (1, "Tab #2")]);
        assert_eq!(assign_slots(&t), vec![(1, "4")]);
        // 素早い連打で2つ同時でも別のスロットになる
        let t = tabs(&[(0, "3"), (1, "Tab #2"), (2, "Tab #3")]);
        assert_eq!(assign_slots(&t), vec![(1, "4"), (2, "2")]);
        // 空き番号の再利用（3,2,8 使用中 → 4）
        let t = tabs(&[(0, "3"), (1, "2"), (2, "8"), (3, "Tab #5")]);
        assert_eq!(assign_slots(&t), vec![(3, "4")]);
    }

    #[test]
    fn スロット割り当ての対象外と枯渇() {
        // デフォルト名のタブがなければ何もしない
        let t = tabs(&[(0, "3"), (1, "logs")]);
        assert_eq!(assign_slots(&t), vec![]);
        // 手動リネームされた名前は使用中として避ける
        let t = tabs(&[(0, "4"), (1, "Tab #9")]);
        assert_eq!(assign_slots(&t), vec![(1, "3")]);
        // 全スロット使用中は割り当てない（デフォルト名のまま残る）
        let mut all: Vec<(usize, String)> = SLOT_PRIORITY
            .iter()
            .enumerate()
            .map(|(i, s)| (i, s.to_string()))
            .collect();
        all.push((10, "Tab #11".to_string()));
        assert_eq!(assign_slots(&all), vec![]);
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

    fn nt(v: &[(&str, &str)]) -> Vec<(String, String)> {
        v.iter()
            .map(|(n, t)| (n.to_string(), t.to_string()))
            .collect()
    }

    #[test]
    fn 幅が足りればラベルはそのまま() {
        assert_eq!(
            fit_labels(&nt(&[("3", "vim"), ("4", "fish")]), 80),
            vec![" 3:vim ", " 4:fish "]
        );
    }

    #[test]
    fn 幅が足りなければタイトルを均等に切り詰める() {
        // 固定部: " N "×2=6 + コロン2 = 8。available=16 → タイトル予算 8/2=4
        assert_eq!(
            fit_labels(&nt(&[("3", "abcdefgh"), ("4", "xyzxyzxy")]), 16),
            vec![" 3:abcd ", " 4:xyzx "]
        );
    }

    #[test]
    fn 切り詰めてもスロット番号は全て残る() {
        let labels = fit_labels(&nt(&[("3", "aaaa"), ("4", "bbbb"), ("2", "cccc")]), 9);
        assert_eq!(labels.len(), 3);
        assert!(labels[0].contains('3'));
        assert!(labels[1].contains('4'));
        assert!(labels[2].contains('2'));
    }

    #[test]
    fn タイトルなしやスロット外の名前も維持される() {
        assert_eq!(
            fit_labels(&nt(&[("3", ""), ("logs", "x")]), 80),
            vec![" 3 ", " logs "]
        );
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
