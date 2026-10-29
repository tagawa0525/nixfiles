//! guard-git-amend: 先端が既定ブランチに含まれる feature ブランチでの `git commit --amend` を止める
//!
//! 既定ブランチから作ったばかりのブランチの先端は、既定ブランチのコミット（多くはマージコミット）である。
//! 最初の `git commit` が hook（commit-msg など）に拒まれたのに気づかずに amend すると、そのコミットを
//! 書き換えたもの（マージコミットなら親 2 つ）がブランチの最初のコミットになる。
//!
//! 止めるのは、今のブランチが名前のあるブランチで既定ブランチでなく、その先端が既定ブランチ（[`git::default_branch`]
//! の ref と、そのローカルのブランチのどちらか）に含まれる（`git merge-base --is-ancestor`）ときだけ。既定ブランチの上の
//! amend（マージの直後にマージコミットの本文を直す）、detached HEAD（rebase の途中の edit）、ブランチに固有のコミットが
//! あるときは通す。
//!
//! hook は実行前の状態しか見られない。同じコマンドの前に、同じディレクトリでブランチの先端や HEAD を動かしうる git の
//! コマンド（commit、switch、checkout、reset など）があると、amend が書き換えるコミットは前のコマンドの成否と中身で
//! 決まる（`git commit -m a; git commit --amend` は、前の commit が拒まれれば既定ブランチのコミットを書き換える。
//! `git switch -C b && …` や `git reset --soft main && …` は先端を既定ブランチへ移す）。書き方から決められないので、
//! 止める側に倒し、呼び出しを分けるよう示す（分ければ次の呼び出しは動いた後の状態で判定される）。ただし既定ブランチの上で、
//! 前のコマンドがブランチを移らない（switch / checkout でない）なら、amend は既定ブランチの上のものなので通す。
//! エスケープは無い。既定ブランチのコミットを feature ブランチで書き換えて残す正当な手順が無いため。比べた案は ADR-0069。

use super::Rule;
use crate::git;
use crate::git_args::{Item, items};
use crate::input::Input;
use crate::output::Finding;
use crate::shell::{Arg, Cmd, Shell};
use std::path::Path;

pub struct GuardGitAmend;

/// 字面のままでは値が決まらない引数（変数やコマンドの置き換え）
fn unexpanded(text: &str) -> bool {
    text.contains('$') || text.contains('`')
}

/// 前の `git <sub> args…` がブランチの先端か HEAD を動かしうるか。`reset` は、パスを渡さずに 1 つのコミットを指す
/// ときだけ（`reset HEAD -- <path>` や `reset <path>` は index しか変えない）。`checkout` は、ブランチを作る・切り離す
/// オプションか、パスを渡さずに 1 つの引数を指し、それが `-`、コミット、作業ツリーに無い名前（リモートにだけある
/// ブランチは git が追跡ブランチを作って移る）のどれかのとき。値の決まらない引数は止める側に倒す（ADR-0025）。
/// `branch` は既にあるブランチを動かす `-f` の形だけ
fn moves_tip(dir: &Path, sub: &str, args: &[Arg]) -> bool {
    let (before, after) = match args.iter().position(|a| a.text == "--") {
        Some(i) => (&args[..i], &args[i + 1..]),
        None => (args, &[][..]),
    };
    let positional: Vec<&str> = before
        .iter()
        .map(|a| a.text.as_str())
        .filter(|t| !t.starts_with('-') || *t == "-")
        .collect();
    let names_commit = |t: &str| {
        unexpanded(t)
            || git::git(
                dir,
                &[
                    "rev-parse",
                    "--verify",
                    "--quiet",
                    &format!("{t}^{{commit}}"),
                ],
            )
            .is_some()
    };
    let single = match positional.as_slice() {
        [t] if after.is_empty() => Some(*t),
        _ => None,
    };
    match sub {
        "commit" | "switch" | "merge" | "rebase" | "pull" | "cherry-pick" | "revert" | "am"
        | "update-ref" => true,
        "reset" => single.is_some_and(names_commit),
        "checkout" => {
            let creates = before.iter().any(|a| {
                let t = a.text.as_str();
                matches!(t.split('=').next(), Some("--orphan" | "--detach"))
                    || t.strip_prefix('-').is_some_and(|c| {
                        !c.starts_with('-') && (c.contains('b') || c.contains('B'))
                    })
            });
            creates || single.is_some_and(|t| t == "-" || names_commit(t) || !dir.join(t).exists())
        }
        "branch" => args.iter().any(|a| {
            a.text == "--force"
                || a.text
                    .strip_prefix('-')
                    .is_some_and(|c| !c.starts_with('-') && c.contains('f'))
        }),
        _ => false,
    }
}

/// 前の `git <sub>` が今のブランチから移りうるか（既定ブランチの上に留まるかの判定に使う）。`rebase <upstream> <branch>` は
/// 先に <branch> へ移る
fn may_leave_branch(sub: &str) -> bool {
    matches!(sub, "switch" | "checkout" | "rebase")
}

/// `git commit` の引数が amend を指すか。git は一意な略（`--am`、`--no-am` など）を受け付け、後に書いた
/// `--no-amend` が前の `--amend` を打ち消す。値（`-m --amend`）と `--` の後の pathspec は数えない
fn is_amend(cmd: &Cmd) -> bool {
    let Some(("commit", args)) = cmd.git_subcommand() else {
        return false;
    };
    // `--a` は --all / --author などと、`--no-a` は --no-all などと紛れるので略にならない
    let abbreviates =
        |full: &str, name: &str, min: usize| name.len() >= min && full.starts_with(name);
    let mut amend = false;
    for item in items("commit", args) {
        if let Item::Long(name) = item {
            if abbreviates("--amend", name, 4) {
                amend = true;
            } else if abbreviates("--no-amend", name, 7) {
                amend = false;
            }
        }
    }
    amend
}

/// cmd より前に、同じディレクトリを対象にして先端か HEAD を動かしうる git のコマンド（[`moves_tip`]）。サブシェルとコマンドの
/// 置き換えの中のものも数える（cwd と違い、リポジトリの状態はサブシェルの外にも残る）
fn earlier_tip_moves<'a>(shell: &'a Shell, cmd: &Cmd, base: &Path, dir: &Path) -> Vec<&'a Cmd> {
    shell
        .commands()
        .iter()
        .filter(|c| {
            c.start < cmd.start
                && shell.target_dir(c, base) == dir
                && c.git_subcommand()
                    .is_some_and(|(sub, args)| moves_tip(dir, sub, args))
        })
        .collect()
}

/// HEAD が既定ブランチの ref（`origin/main` など）か、そのローカルのブランチ（push していないマージを含む）に含まれるか
fn contained_in_default(dir: &Path, default_ref: &str, default: &str) -> bool {
    let local = format!("refs/heads/{default}");
    [default_ref, local.as_str()]
        .iter()
        .any(|r| git::git(dir, &["merge-base", "--is-ancestor", "HEAD", r]).is_some())
}

impl Rule for GuardGitAmend {
    fn name(&self) -> &'static str {
        "guard-git-amend"
    }

    fn check(&self, input: &Input, shell: &Shell) -> Vec<Finding> {
        for cmd in shell.commands() {
            if !is_amend(cmd) || shell.runs_under_ssh_or_login(cmd) {
                continue;
            }
            let dir = shell.target_dir(cmd, &input.cwd);
            let branch = git::current_branch(&dir);
            let default_ref = git::default_branch(&dir);
            let default = default_ref.as_deref().map(git::local_name);
            let moves = earlier_tip_moves(shell, cmd, &input.cwd, &dir);
            // 既定ブランチの上で、ブランチを移らない前のコマンド（merge、commit、reset）の後の amend は、既定ブランチの上の amend
            let stays_on_default = default == Some(branch.as_str())
                && moves.iter().all(|c| {
                    c.git_subcommand()
                        .is_some_and(|(sub, _)| !may_leave_branch(sub))
                });
            if let Some(prev) = moves.first().filter(|_| !stays_on_default) {
                let raw: Vec<&str> = prev.args.iter().map(|a| a.raw.as_str()).collect();
                return vec![Finding::Deny(format!(
                    "同じコマンドの前の `{} {}` がブランチの先端か HEAD を動かしうるので、git commit --amend が書き換える\
                     コミットを実行前に決められません（前の git commit が hook に拒まれると、amend は今の先端を書き換えます。\
                     先端が既定ブランチのコミットなら、それを書き換えたものがブランチに入ります）。\n\
                     amend は別の呼び出しに分けてください。分けた amend は、前のコマンドの後の状態で判定します。",
                    prev.name,
                    raw.join(" ")
                ))];
            }
            let (Some(default_ref), Some(default)) = (default_ref.as_deref(), default) else {
                continue;
            };
            if branch.is_empty()
                || branch == default
                || !contained_in_default(&dir, default_ref, default)
            {
                continue;
            }
            let mut msg = format!(
                "ブランチ {branch} の先端は既定ブランチ（{default_ref}）に含まれるコミットです。ここで amend すると、\
                 既定ブランチのコミット（多くはマージコミット）を書き換えたもの（マージコミットなら親 2 つ）が\
                 ブランチの最初のコミットになります。\n\
                 - 直前の git commit が hook に拒まれていないかを git log -1 で確かめる（-q や ; のつなぎでは失敗が見えません）\n\
                 - ブランチの最初のコミットを作るなら、amend せず git commit で新しいコミットを作る"
            );
            if !git::has_github_remote(&dir) {
                msg.push_str(&format!(
                    "\n- push していない既定ブランチのコミット（マージの直後のマージコミットの本文など）を直すのが意図なら、\
                     {default} の上で amend する"
                ));
            }
            return vec![Finding::Deny(msg)];
        }
        Vec::new()
    }
}
