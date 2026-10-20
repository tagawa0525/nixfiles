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

(b) を採る。コマンド文字列全体が `&&` だけでつないだ単純コマンドの連鎖 1 つで、`gh pr create`（`--head` なし）が
その最後にあり、左の中身が `cd` と、次をすべて満たす `git push` 1 つだけなら、検査 3 を省く。

連鎖の外に文を許さないのは、前に `;` や改行で置いた文（`git switch -c b; git push -u origin <元のブランチ> && …`）が
gh のブランチを変え、関数の定義（`git() { …; }; git push …`）が `git` や `cd` の意味を変えるため。後ろの
`|| …`、連鎖を包むリダイレクト（`… && gh pr create … > out.txt` は tree-sitter-bash では連鎖全体を包む）や
サブシェル、`bash -c '…'` の文字列の中の連鎖も、外側に文が並びうるので認めない。

`cd` 以外のコマンドを許さないのは、push の後でブランチを切り替える・コミットする・上流を外す
（`git switch -c other`、`git commit`、`git branch --unset-upstream`）と gh は上流の無い状態で走り、push の前で
ブランチを切り替えると、名前で指定した push（下の 3 つめの形）が gh のブランチの上流にならないため。hook は
実行前の状態しか見ないので、どのコマンドが状態を変えないかを個別に判定せず、ディレクトリだけを動かす `cd`
（行き先は下の対象のディレクトリの比較で確かめる）に限る。

- サブコマンドの引数が次のどれか。`-u` は `--set-upstream` でもよく、位置は問わない。引数は guard-git-push と同じ
  `git_args::items` で読む（`--` の後は位置引数）
  - 引数なしの `git push`（`-u` だけを付けたものを含む）。`push.default` が未設定（既定の `simple`）か `simple` の
    ときだけ。`simple` は成功すれば現在のブランチを同じ名前の上流へ push してある（上流が無ければ失敗して gh は
    走らず、`push.autoSetupRemote` があれば上流を設定する）。`current` は `push.autoSetupRemote` が無いと上流を
    設定せずに成功し、`matching` は現在のブランチを push せずに成功しうる。`upstream`（`tracking`）は名前の違う
    上流（`origin/main` を追うブランチ）へ push するので認めない。押し先を別に決める設定（`remote.pushDefault`、
    `branch.<名前>.pushRemote` の三角の構成、`remote.<名前>.push`、`remote.<名前>.mirror`）がある clone でも、
    `simple` が上流を設定せずに成功しうるので認めない。設定は現在のブランチとリモートに限らず、どれかがあれば
    認めない（安全側）
  - `git push -u origin HEAD`
  - `git push -u origin <現在のブランチ名>`（`git branch --show-current` と一致。detached HEAD では空なので一致しない）
- ほかのオプション（`--dry-run`、`-n`、`--force` など）、refspec（`HEAD:<ブランチ>`）、3 つ以上の位置引数、
  `origin` 以外のリモートを含まない。`-u` の無い `git push origin HEAD` は上流を設定しないので認めない
- 前置きの代入（`GIT_DIR=…`）、包み（`env`、`sudo` など）、`-C <dir>` 以外の git の全体オプション（`-c`、
  `--git-dir`、`--work-tree` など）が無く、走らせるプログラムが決まり
  （`Cmd::opaque` でない）、構文エラーが無い
- push の対象のディレクトリ（`cd`、`git -C` を当てたもの）が gh の対象のディレクトリと同じ

連鎖の判定は shell.rs が `Cmd::after`（そのコマンドが走るときに成功していた単純コマンドの位置）として持ち、
`Shell::succeeded_before` で引く。tree-sitter-bash は `a && b && c` を `(list (list a b) c)` と左に結合して読むので、
右オペランドの左側を `&&` の `list` だけたどって単純コマンドを集める。左側のどこかに `||` を含む `list`、
パイプライン、`!`、`(…)`、`{ …; }`、ループ、代入、リダイレクトの付いた文、置換（`$(…)`）を含むコマンドがあれば、
連鎖全体を集めない（その中で何が走ったか、push が成功したかを構文から言えない。飛ばして残りを集めると、
`(git switch -c other) && …` のような中身を見落とす）。
`Cmd::after` はトップレベルのコマンドだけが持つ（文字列の中のコマンドの位置は外側の位置に寄せてあり、外側の
置換の中のコマンドと重なりうる）。

deny の文言は、別の呼び出しに分ける案内から、`&&` でつなぐ書き方の案内に変える。

## 帰結

- `git push -u origin HEAD && gh pr create …` を 1 回で投げられる。スキルの「別の呼び出しに分ける」規則は要らなく
  なる
- 認める形から外れた push（別のリモート、refspec、`;` でつないだものなど）は今までどおり deny する。文言で認める形を
  示す
- `git push 2>&1 && gh pr create …` のようにリダイレクトを付けた push、`… && gh pr create … > out.txt` や
  `… && gh pr create … || echo failed` のように連鎖の外に何かを置いたもの、`!` やパイプで包んだ gh は認めない
  （安全側の deny）。必要になれば、包みが push の成否と gh の実行を変えないことを確かめて広げる
- `cd .. && cd repo` やサブディレクトリへの `cd` のように、push と gh の対象のディレクトリの書き方が違うと、
  同じリポジトリでも deny する（パスの字面で比べる）
- 連鎖の中や前に `git fetch` などの状態を変えないコマンドを置いても deny する。前に要るなら別の呼び出しにする
- 連鎖の判定は、トップレベルの `&&` の連鎖ごとに左を集めるので、連鎖の長さの 2 乗に比例する。連鎖は数個の
  コマンドで、hook が起こす git のプロセスより十分に軽い

## 確認

- `src/shell.rs` の単体テストで、`Shell::succeeded_before` が `&&` の連鎖の左だけを返し、`;`、`||`、`&`、パイプ、
  改行、包む構文の中を返さないこと、連鎖の外に文がある、または文字列の中の連鎖なら空を返すことを確かめる
- `.claude/tests/hooks.sh` の pre-pr-create-check の節で、上の 3 つの形（`cd` と `git -C` を含む）が上流の無い
  ブランチで通り、外れた形と、push の前後に `cd` 以外のコマンドを置いた連鎖、連鎖の外の文、`-C` 以外の git の全体オプションが deny されること、
  `push.default` が `current`、`matching`、`upstream` のときと押し先を別に決める設定があるときは引数なしの push を
  認めないこと、push を前に連ねても検査 1、2、4 が残ることを確かめる
