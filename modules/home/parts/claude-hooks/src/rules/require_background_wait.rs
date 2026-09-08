//! require-background-wait: レビュー待機スクリプトの誤った起動を止める
//!
//! 1. フォアグラウンド実行
//!    gh-wait-review.sh / request-rereview.sh は漸増バックオフで約 10 分待つため、Bash ツールの
//!    フォアグラウンド上限を必ず超えて失敗する。run_in_background=true でのみ許可する
//! 2. request-rereview.sh に gh-wait-review.sh を続ける二重待機
//!    request-rereview.sh は要求から待機までを一体で行う。後ろに gh-wait-review.sh を続けると、
//!    直前に届いたレビューを基準に「次のレビュー」を待つことになり、要求していない以上必ず
//!    約 10 分タイムアウトする。その間モデルは待機中だと思い込み、既に届いたレビューに
//!    気づけない（2026-09-08 に実際に起きた）
//! 3. パイプへの接続
//!    `… | tail -3` のようにつなぐと終了コードが右端のコマンドのものになり、
//!    レビュー到着(0)とタイムアウト(1)を区別できない。出力を残したいならリダイレクトを使う
//!
//! 回避する正当な理由がないため、エスケープは設けない。
//! `echo request-rereview.sh` や `cat …` のように引数に現れるだけの場合は対象外。

use super::Rule;
use crate::input::Input;
use crate::output::Finding;
use crate::shell::{Cmd, Shell};

pub struct RequireBackgroundWait;

const WAIT: &str = "gh-wait-review.sh";
const REREVIEW: &str = "request-rereview.sh";
const SCRIPTS: &[&str] = &[WAIT, REREVIEW];

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// 実行しているスクリプト名（直接、または `bash <path>` / `sh <path>` 経由）
fn wait_script(cmd: &Cmd) -> Option<&'static str> {
    let name = if (cmd.name == "bash" || cmd.name == "sh")
        && let Some(first) = cmd.args.first()
    {
        basename(&first.text)
    } else {
        basename(&cmd.name)
    };
    SCRIPTS.iter().find(|s| **s == name).copied()
}

impl Rule for RequireBackgroundWait {
    fn name(&self) -> &'static str {
        "require-background-wait"
    }

    fn check(&self, input: &Input, shell: &Shell) -> Vec<Finding> {
        let cmds = shell.commands();
        let used: Vec<(&'static str, bool)> = cmds
            .iter()
            .filter_map(|c| wait_script(c).map(|s| (s, c.piped_out)))
            .collect();
        if used.is_empty() {
            return Vec::new();
        }

        if !input.run_in_background {
            return vec![Finding::Deny(
                "gh-wait-review.sh / request-rereview.sh は約10分待機するため、Bash ツールの run_in_background=true で実行してください（フォアグラウンドでは上限に達して必ず失敗します）".to_string(),
            )];
        }

        if used.iter().any(|(s, _)| *s == REREVIEW) && used.iter().any(|(s, _)| *s == WAIT) {
            return vec![Finding::Deny(
                "request-rereview.sh は要求から待機までを一体で行うため、続けて gh-wait-review.sh を実行しないでください。直前に届いたレビューを基準に「次のレビュー」を待つことになり、要求していない以上かならず約10分タイムアウトします（その間、既に届いているレビューに気づけません）。request-rereview.sh だけを実行してください".to_string(),
            )];
        }

        if used.iter().any(|(_, piped)| *piped) {
            return vec![Finding::Deny(
                "gh-wait-review.sh / request-rereview.sh をパイプにつながないでください。終了コードが右端のコマンドのものになり、レビュー到着(0)とタイムアウト(1)を区別できなくなります。出力を残すならリダイレクト（> file 2>&1）を使ってください".to_string(),
            )];
        }

        Vec::new()
    }
}
