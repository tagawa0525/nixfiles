---
status: accepted
date: 2026-10-20
requires: []
supersedes: []
superseded-by:
issues: ["#388"]
---

# ADR-0040: 同じ && の連鎖で先に現在のブランチを push する gh pr create は、上流と未プッシュの検査を省く

## 背景

`pre-pr-create-check`（`modules/home/parts/claude-hooks/src/rules/pre_pr_create_check.rs`）の検査 3 は、現在の
ブランチに上流があり、未プッシュのコミットが無いことを求める（上流が無いと gh が対話的に push 先を尋ねて固まる）。
PreToolUse の hook はコマンドの実行前に走るので、検査 3 は実行前の状態を見る。

そのため `git push -u origin HEAD && gh pr create …` を 1 回で投げると、上流が無い・未プッシュとして deny され、
コマンド全体が止まるので前半の push も走らない。2026-10-20 に 3 回起きた（#388）。PR #384 は deny の文言に
「push と gh pr create は別の呼び出しに分ける」を足し、スキル（gh-pr-create、delegate）にも同じ規則を書いて、
hook の制約を手順側で補った。

## 決定の要因

- 根本の原因は、検査が実行前の状態を見ることにある。手順の規則で補うと、書き方を覚えておく負担と、止められて
  投げ直す手間が残る
- `&&` の右は左が成功したときだけ走る。左の push が失敗すれば gh は走らないので、gh が push 前の状態で走ることは
  無い
- hook の検査条件を緩めるので、通す範囲は、push 後の状態が検査 3 を満たすと構文と引数だけで言えるものに限る
- 検査 1、2、4（`--title`、本文、`--web`）と `--head` を指定したときの扱いは、push と関係が無いので変えない

## 検討した案

- (a) 文言とスキルの規則で、push と gh pr create を別の呼び出しに分けさせる（PR #384 の現状）。検査条件は
  変わらず安全だが、書き方を間違えるたびに止まり、前半の push も走らない
- (b) 同じ `&&` の連鎖で gh pr create より前に、現在のブランチを push する決まった形の `git push` があれば、検査 3 を
  省く（採用）
- (c) (b) で、`git push` の引数を広く読む（任意のリモート名、`HEAD:<ブランチ>` の refspec、`--force` などの
  オプション）。push 先が現在のブランチの上流になるかは、リモートの設定、`push.default`、refspec の解釈に依り、
  hook で決めるには git の挙動を作り直すことになる。誤って通すと gh が固まるので採らない
- (d) hook で push を先に実行する、または検査 3 を実行後の状態に先送りする。PreToolUse の hook はコマンドを
  書き換えずに許可か拒否を返すもので、副作用を持たせない
- (e) `;`、改行、`||` でつないだ push も認める。`;` と改行は push が失敗しても gh が走り、`||` は push が失敗した
  ときに走るので、gh が上流の無い状態で走りうる。採らない

## 決定と理由

(b) を採る。hook は実行前の状態しか見ないので、push 後の状態が検査 3 を満たすと構文、引数、git の設定から言える
ものだけを通し、言えないものは今までどおり deny する（安全側）。境界は次の 3 つの原則で決める。個々の書き方の
扱いは `pre_pr_create_check.rs` の `pushed_before` / `pushes_current_branch` と `.claude/tests/hooks.sh` の
テストが正である。

1. **連鎖の形**: コマンド文字列全体が `&&` だけでつないだ単純コマンドの連鎖 1 つで、`gh pr create`（`--head`
   なし）がその最後にある。連鎖の外の文（前の `;` や改行の文、関数の定義、後ろの `|| …`、連鎖を包む
   リダイレクトやサブシェル、`bash -c` の文字列）と、連鎖の中の単純コマンドでないもの（パイプ、`!`、`(…)`、
   `{ …; }`、代入、リダイレクトや置換を含むコマンド）は、その中で何が走り、`git` や `cd` が何を指すかを構文から
   言えないので、あれば連鎖全体を数えない
2. **連鎖の中身**: gh の左は、前置きの代入や包みの無い `cd` と、認める形の `git push` 1 つだけ。ほかのコマンドは、
   push の後でブランチを切り替える・コミットする・上流を外す、push の前でブランチを切り替えるなど、gh の
   ブランチの状態を変えうる。状態を変えないかを個別に判定しない
3. **push の形**: push 先が現在のブランチの、同じ名前の上流になると決まるもの。`git push -u origin HEAD`、
   `git push -u origin <現在のブランチ>`、`push.default` が `simple`（既定）で押し先を別に決める設定
   （`remote.pushDefault`、`branch.<名前>.pushRemote`、`remote.<名前>.push`、`remote.<名前>.mirror`）の無い
   引数なしの `git push`。ほかのオプション、refspec、`-C` 以外の git の全体オプション、前置きの代入、包みは
   認めない。push と gh の対象のディレクトリ（`cd`、`git -C` を当てたもの）とリポジトリ（gh の前置きの代入、
   包み、`-R`）が同じで、origin の fetch の refspec が `refs/heads/*` を追う（追わない clone では push 後も
   `@{u}` が解決しない）

連鎖の判定は shell.rs の `Shell::succeeded_before` が持つ。

deny の文言は、別の呼び出しに分ける案内から、`&&` の連鎖の書き方の案内に変える。

## 帰結

- `git push -u origin HEAD && gh pr create …` を 1 回で投げられる。スキルの「別の呼び出しに分ける」規則は要らなく
  なる
- 安全側に倒した結果、push の成否と gh の実行を変えない書き方（push の `2>&1`、連鎖の後ろの `|| echo`、連鎖の中の
  `git fetch`、別の書き方の同じディレクトリへの `cd`、関係の無いブランチの `pushRemote` など）も deny する。
  必要になれば、その書き方が push 後の状態を変えないことを確かめて広げる

## 確認

- `src/shell.rs` の単体テストで、`Shell::succeeded_before` の連鎖の形の境界を確かめる
- `.claude/tests/hooks.sh` の pre-pr-create-check の節で、認める形が上流の無いブランチで通り、上の原則から外れる
  形が deny されること、push を前に連ねても検査 1、2、4 が残ることを確かめる

## 補足

### 試して捨てた方式

PR #402 のローカルのレビューで、作り直す前の版にそれぞれ次の反例が見つかった（すべて上流の無いブランチで
hook が通し、gh が上流の無い状態で走る）。

- 連鎖の左の中身を問わない版: `git push -u origin HEAD && git switch -c other && gh pr create …`
- 連鎖の中の単純コマンドでない部分を飛ばして残りを集める版: `git push -u origin HEAD && (git switch -c other) &&
  gh pr create …`、`git switch -c other || true && git push -u origin <元のブランチ> && gh pr create …`
- gh が `&&` の右にあれば連鎖の外の文を問わない版: `git switch -c b; git push -u origin <元のブランチ> &&
  gh pr create …`、`git() { command git switch -c q; }; git push -u origin HEAD && gh pr create …`。また、
  文字列の中のコマンドの寄せた位置が外側の置換の中のコマンドと重なり、`env A=$(a) bash -c 'true;  git push &&
  gh pr'` で `a` を成功していたものと数えた
- 引数なしの push を `push.default` の `upstream` でも認める版: `origin/main` を追うブランチの commit が main へ
  push される。押し先の設定を見ない版: `remote.pushDefault` や `remote.origin.mirror` で上流が設定されない
- `git -c` だけを弾く版: `git --git-dir=/other/.git push -u origin HEAD && gh pr create …`
- origin の fetch の refspec を見ない版: `--single-branch` の clone で push 後も `@{u}` が解決しない
