// =============================================================================
// zellij-slots: スロット式タブ管理プラグイン
// =============================================================================
// Zellij のタブは位置ベースで、閉じると後続が詰められ固定番号を持てない。
// そこでタブ「名」をスロット番号として扱い、tmux の window 番号運用を再現する:
//   - new:    優先順位で空いているスロット番号を名前にしてタブを作成
//   - goto:N: その名前のタブへフォーカス（不在なら何もしない）
// キーバインドの MessagePlugin から name="slots" のパイプで呼び出される。
// =============================================================================
use std::collections::BTreeMap;

use zellij_tile::prelude::*;

/// スロット番号の優先順位（押しやすい順）。tmux.nix の windowPriority と同じ
const SLOT_PRIORITY: [&str; 10] = ["3", "4", "2", "8", "7", "9", "5", "6", "1", "0"];

/// パイプの名前。キーバインド側の MessagePlugin と一致させる
const PIPE_NAME: &str = "slots";

/// 優先順位で最初に空いているスロット番号を返す。全て使用中なら None
fn find_free_slot(used: &[String]) -> Option<&'static str> {
    todo!()
}

#[derive(Default)]
struct State {
    tab_names: Vec<String>,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[EventType::TabUpdate]);
    }

    fn update(&mut self, event: Event) -> bool {
        if let Event::TabUpdate(tabs) = event {
            self.tab_names = tabs.into_iter().map(|t| t.name).collect();
        }
        false
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        let _ = message;
        false
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
}
