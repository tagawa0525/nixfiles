//! pre-pr-create-check: gh pr create の前提条件を検証する
//!
//! gh-pr-create スキルの手順のうち、コマンド文字列と git の状態だけで決定的に判定できるものを
//! ゲートにする（スキルを経由しない gh pr create にも効く）:
//! 1. --title がある（--fill は使わない）。fork でなければ 70 文字以内
//! 2. --body / --body-file がある。fork でなければ本文に ## Summary / ## Changes / ## Tests が
//!    揃っている（見出しは常に英語。本文の言語は問わない。--body を省くと gh がエディタを
//!    開き、Claude Code セッションでは固まる）
//! 3. 現在のブランチに上流があり、未プッシュのコミットがない（--head 指定時は見ない）。
//!    検査は実行前の状態を見るので、同じ `&&` の連鎖で先に現在のブランチを push するとき
//!    （`git push -u origin HEAD && gh pr create …`）は見ない。push が失敗すれば gh は走らない（ADR-0040）
//! 4. --web を使わない（ブラウザを開かず URL を報告する）
//!
//! 本文の見出しは `--body` 引数ノードの原文（ヒアドキュメント本文を含む）だけを見る。
//! 別のヒアドキュメントに書かれた見出しの例でゲートを通すことはできない。
//! エスケープは設けない（いずれも満たしてから実行し直せばよい）
//!
//! `upstream` リモートのある clone（他人のプロジェクトの fork。上流に PR を出す worktree）では、
//! 件名の長さと本文の見出しはこちらの規約なので検査しない。上流の PR template と
//! CONTRIBUTING が正で、それに合わせた本文（Serena の Checklist 等）を通す。
//! --title と本文の存在、--web、未プッシュの検査は fork でも要る（gh が固まる・失敗する条件）。
//! git の pre-commit / commit-msg hook と同じ判定（modules/home/parts/git.nix）

use std::path::Path;

use super::Rule;
use crate::git;
use crate::git_args::{Item, items};
use crate::input::Input;
use crate::output::Finding;
use crate::shell::{Arg, Cmd, Shell, has_flag, opt_value};

/// 検査は実行前のブランチの状態を見る。認める形でない push を前に連ねるとコマンド全体が止まって
/// 前半も実行されないので、認める形を deny の文言で示す。
const CHAINED_PUSH_HINT: &str = "同じ呼び出しで push するなら、git push -u origin HEAD && gh pr create … のように、コマンド全体を && でつないだ連鎖 1 つにしてください（gh は最後に置き、ほかに置けるのは cd だけです。; や || や改行でつないだ文、リダイレクトやほかのオプションを付けた push、別のリモートやブランチへの push は検査に反映されません）";

/// コマンドに git push があるのに検査 3 を省けなかったときの案内。同じ書き方を勧めると、同じコマンドを投げ直し
/// 続ける（反映できない理由は clone の設定などにもあり、文言では列挙しない）
const REJECTED_PUSH_HINT: &str = "同じ呼び出しの git push は、検査に反映できる形ではありません（認める形は nixfiles の ADR-0040）。push を別の呼び出しにして、終わってから gh pr create を実行してください";

pub struct PrePrCreateCheck;

/// 実行前の状態で、現在のブランチに上流が無いか未プッシュのコミットがあれば、その理由
fn unpushed_reason(dir: &Path, hint: &str) -> Option<String> {
    let Some(upstream) = git::git(
        dir,
        &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
    ) else {
        return Some(format!(
            "現在のブランチに上流ブランチがありません。先に git push してください（gh が対話的に push 先を尋ねて固まるのを防ぐ）。{hint}"
        ));
    };
    let ahead =
        git::git(dir, &["rev-list", "--count", "@{u}..HEAD"]).unwrap_or_else(|| "?".to_string());
    if ahead == "0" {
        return None;
    }
    // 件数が取れなかった（"?"）ときは原因が未プッシュとは限らないので、書き方は示さない
    let hint = if ahead == "?" {
        String::new()
    } else {
        format!("。{hint}")
    };
    Some(format!(
        "未プッシュのコミットが {ahead} 件あります（{upstream} より先）。先に git push してください{hint}"
    ))
}

/// 連鎖の push の形。押し先の設定のうち、どれが push の行き先を変えるかが形で違う
#[derive(Clone, Copy, PartialEq)]
enum PushForm {
    /// 引数なし（`-u` だけを含む）。ブランチのリモート、`push.default`、押し先の設定で行き先が決まる
    Bare,
    /// `-u origin HEAD` / `-u origin <現在のブランチ>`
    Explicit,
}

/// gh pr create の前に、同じ `&&` の連鎖で dir の現在のブランチを push するか。連鎖の左は `cd` と、認める形の
/// git push 1 つだけにする。push の後でブランチを切り替える・コミットする・上流を外すコマンドや、push の前で
/// ブランチを切り替えるコマンド（名前で指定した push が gh のブランチの上流にならない）を通さない（ADR-0040）
///
/// gh の対象を push と別のリポジトリにするもの（前置きの代入の `GIT_DIR` や `GH_REPO`、包み、`-R`）があれば通さない
fn pushed_before(gh: &Cmd, shell: &Shell, base: &Path, dir: &Path) -> bool {
    let Some(gh_args) = gh.gh_subcommand(&["pr", "create"]) else {
        return false;
    };
    // `-Rowner/repo` の付け書きも gh は受ける
    if !gh.env.is_empty()
        || !gh.wrappers.is_empty()
        || has_flag(gh_args, &["--repo"])
        || gh_args.iter().any(|a| a.text.starts_with("-R"))
    {
        return false;
    }
    let mut push = None;
    for c in shell.succeeded_before(gh) {
        match pushes_current_branch(c, shell, base, dir) {
            Some(form) if push.is_none() => push = Some(form),
            Some(_) => return false,
            None if is_plain_cd(c) => {}
            None => return false,
        }
    }
    push.is_some_and(|form| push_config_keeps_upstream(dir, form))
}

/// 1 つの行き先へ移るだけの cd か。前置きの代入（CDPATH）、builtin などの包み、`cd -` や引数なしは、target_dir の
/// 読む行き先と実際の行き先を食い違わせうる
fn is_plain_cd(cmd: &Cmd) -> bool {
    cmd.changes_dir()
        && cmd.env.is_empty()
        && cmd.wrappers.is_empty()
        && matches!(cmd.args.as_slice(), [a] if !a.text.starts_with('-'))
}

/// push が成功したなら、現在のブランチに同じ名前の、解決できる上流があると git の設定から言えるか
///
/// - `remote.<名前>.push` は名前で指定した push の行き先も書き換え、`remote.<名前>.mirror` は refspec と並べると
///   push が失敗し、引数なしでは上流を設定しない
/// - `push.default=upstream`（`tracking`）は、名前で指定した push も上流の名前（origin/main を追うブランチなら
///   main）へ書き換える。引数なしの push は simple（既定）だけを認める。current は push.autoSetupRemote が無いと
///   上流を設定せず、matching は現在のブランチを push しないことがある
/// - 引数なしの push はブランチのリモート（`branch.<名前>.remote`）へ行き、`remote.pushDefault` と
///   `branch.<名前>.pushRemote` があればそちらへ行く。origin の refspec で判断できるように、origin へ行くときだけ
/// - origin の fetch の refspec が `refs/heads/*` を追わない clone（`--single-branch`）では、push しても `@{u}` が
///   解決せず、gh が push 先を尋ねる
fn push_config_keeps_upstream(dir: &Path, form: PushForm) -> bool {
    // 1 回の git で読む。何も一致しなければ失敗（None）になるが、origin の fetch の refspec が無い clone も認めない
    let Some(config) = git::git(
        dir,
        &[
            "config",
            "--get-regexp",
            r"^(push\.default|remote\.pushdefault|branch\..*\.(pushremote|remote)|remote\..*\.(push|mirror|fetch))$",
        ],
    ) else {
        return false;
    };
    let branch_remote = format!("branch.{}.remote", git::current_branch(dir));
    let mut tracks_branches = false;
    for line in config.lines() {
        let (key, value) = line.split_once(' ').unwrap_or((line, ""));
        let rejects = match key {
            "push.default" => match form {
                PushForm::Bare => value != "simple",
                PushForm::Explicit => matches!(value, "upstream" | "tracking"),
            },
            "remote.pushdefault" => form == PushForm::Bare,
            "remote.origin.fetch" => {
                tracks_branches |=
                    value.trim_start_matches('+') == "refs/heads/*:refs/remotes/origin/*";
                false
            }
            k if k == branch_remote => form == PushForm::Bare && value != "origin",
            k if k.starts_with("branch.") && k.ends_with(".pushremote") => form == PushForm::Bare,
            k if k.starts_with("remote.") && (k.ends_with(".push") || k.ends_with(".mirror")) => {
                true
            }
            _ => false,
        };
        if rejects {
            return false;
        }
    }
    tracks_branches
}

/// cmd が、dir の現在のブランチを origin へ push するだけの git push なら、その形。認めるのは `git push`、
/// `git push -u origin HEAD`、`git push -u origin <現在のブランチ>`（`-u` は `--set-upstream` でも、位置は問わない）
/// だけで、ほかのオプション、refspec、前置きの代入、包み、`-C` 以外の git の全体オプションは認めない（ADR-0040）。
/// 行き先を変える git の設定は [`push_config_keeps_upstream`] が見る
fn pushes_current_branch(cmd: &Cmd, shell: &Shell, base: &Path, dir: &Path) -> Option<PushForm> {
    let Some(("push", args)) = cmd.git_subcommand() else {
        return None;
    };
    // git の全体オプションは `-C <dir>` だけを認める（`--git-dir`、`--work-tree`、`-c` は push の対象や挙動を変える）。
    // サブコマンドの位置が `-C <dir>` の組の数の 2 倍なら、前にあるのはその組だけ
    if !cmd
        .git
        .as_ref()
        .is_some_and(|g| g.sub == Some(2 * g.dirs.len()))
    {
        return None;
    }
    if cmd.opaque
        || cmd.has_error
        || !cmd.env.is_empty()
        || !cmd.wrappers.is_empty()
        || shell.target_dir(cmd, base) != dir
    {
        return None;
    }
    let mut set_upstream = false;
    let mut positional = Vec::new();
    for item in items("push", args) {
        match item {
            Item::Short('u') | Item::Long("--set-upstream") => set_upstream = true,
            Item::Positional(a) => positional.push(a),
            _ => return None,
        }
    }
    match positional.as_slice() {
        [] => Some(PushForm::Bare),
        // 上流の無いブランチの `git push origin HEAD` は push しても上流を設定せず、gh が push 先を尋ねる
        [remote, refspec] if set_upstream && remote.text == "origin" => {
            let branch = git::current_branch(dir);
            (refspec.text == "HEAD" || (!branch.is_empty() && branch == refspec.text))
                .then_some(PushForm::Explicit)
        }
        _ => None,
    }
}

/// `--x=value` 形式なら value を、そうでなければそのまま
pub(super) fn strip_opt_prefix<'a>(arg: &'a Arg, names: &[&str]) -> &'a str {
    for n in names {
        if let Some(v) = arg.text.strip_prefix(&format!("{n}=")) {
            return v;
        }
    }
    &arg.text
}

/// `~` を展開してファイルを読む
pub(super) fn read_body_file(path: &str) -> Option<String> {
    let path = if let Some(rest) = path.strip_prefix("~/") {
        std::env::var_os("HOME").map(|h| Path::new(&h).join(rest))
    } else {
        Some(Path::new(path).to_path_buf())
    }?;
    std::fs::read_to_string(path).ok()
}

/// 本文に見出しが揃っているか。欠けている見出しを返す
pub(super) fn missing_headings<'a>(body: &str, headings: &[&'a str]) -> Vec<&'a str> {
    headings
        .iter()
        .copied()
        .filter(|h| !body.contains(h))
        .collect()
}

/// `--body` 相当の本文テキスト。--body-file があればその内容（読めなければ Err にパス）
pub(super) fn body_text(
    args: &[Arg],
    body_flags: &[&str],
    file_flags: &[&str],
) -> Result<Option<String>, String> {
    if let Some(f) = opt_value(args, file_flags) {
        let path = strip_opt_prefix(f, file_flags).to_string();
        return match read_body_file(&path) {
            Some(text) => Ok(Some(text)),
            None => Err(path),
        };
    }
    Ok(opt_value(args, body_flags).map(|a| a.raw.clone()))
}

impl Rule for PrePrCreateCheck {
    fn name(&self) -> &'static str {
        "pre-pr-create-check"
    }

    fn check(&self, input: &Input, shell: &Shell) -> Vec<Finding> {
        for cmd in shell.commands() {
            let Some(args) = cmd.gh_subcommand(&["pr", "create"]) else {
                continue;
            };
            let mut reasons: Vec<String> = Vec::new();

            // gh / git の実行コンテキストをコマンドに合わせる（`cd <path> && gh pr create`）
            let mut dir = shell.target_dir(cmd, &input.cwd);
            if !dir.is_dir() {
                // 手元の cwd に戻して続ける検査は、接続先や対象の利用者の PR に当たらないので混ぜない
                if shell.runs_under_ssh_or_login(cmd) {
                    return vec![Finding::Deny(
                        "ssh や sudo -i の中で走る gh は、手元の場所で検査できないため止めます"
                            .to_string(),
                    )];
                }
                reasons.push(format!(
                    "コマンド中の cd 先に移動できません: {}",
                    dir.display()
                ));
                dir = input.cwd.clone();
            }

            // fork ではこちらの規約（件名の長さ、本文の見出し）を検査しない
            let fork = git::is_fork(&dir);

            // --- 4. --web ---
            if has_flag(args, &["--web", "-w"]) {
                reasons.push("--web は使わないでください（ブラウザを開かず、gh pr create が出力した URL を報告する）".to_string());
            }

            // --- 1. タイトル ---
            match opt_value(args, &["--title", "-t"]) {
                Some(t) => {
                    let title = strip_opt_prefix(t, &["--title", "-t"]);
                    let n = title.chars().count();
                    if !fork && n > 70 {
                        reasons.push(format!("--title は 70 文字以内にしてください（現在 {n} 文字）"));
                    }
                }
                None => reasons.push("--title で PR タイトルを指定してください（--fill でコミットメッセージを流用しない）".to_string()),
            }

            // --- 2. 本文 ---
            match body_text(args, &["--body", "-b"], &["--body-file", "-F"]) {
                Err(path) => reasons.push(format!("--body-file のファイルが読めません: {path}")),
                Ok(None) if fork => reasons.push("--body または --body-file で PR 本文を指定してください（上流の PR template に合わせる。省くと gh がエディタを開いて固まる）".to_string()),
                Ok(None) => reasons.push("--body または --body-file で PR 本文を指定してください（## Summary / ## Changes / ## Tests）".to_string()),
                Ok(Some(body)) if !fork => {
                    let missing = missing_headings(&body, &["## Summary", "## Changes", "## Tests"]);
                    if !missing.is_empty() {
                        reasons.push(format!("PR 本文に見出しがありません: {}", missing.join(" ")));
                    }
                }
                Ok(Some(_)) => {}
            }

            // --- 3. 未プッシュコミット ---
            // 連鎖の push を調べるのは、実行前の状態で止めるときだけ（多くは上流が揃っていて git を余計に起こさない）
            let has_push = shell
                .commands()
                .iter()
                .any(|c| matches!(c.git_subcommand(), Some(("push", _))));
            let hint = if has_push {
                REJECTED_PUSH_HINT
            } else {
                CHAINED_PUSH_HINT
            };
            if !has_flag(args, &["--head", "-H"])
                && let Some(reason) = unpushed_reason(&dir, hint)
                && !pushed_before(cmd, shell, &input.cwd, &dir)
            {
                reasons.push(reason);
            }

            if !reasons.is_empty() {
                return vec![Finding::Deny(reasons.join("\n"))];
            }
        }
        Vec::new()
    }
}
