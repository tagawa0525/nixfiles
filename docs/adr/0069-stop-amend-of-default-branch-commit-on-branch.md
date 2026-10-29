---
status: accepted
date: 2026-10-30
requires: [ADR-0023, ADR-0025]
supersedes: []
superseded-by:
issues: []
---

# ADR-0069: 先端が既定ブランチに含まれる feature ブランチでの git commit --amend を hook で止める

## 背景

2026-10-30 01:1x（JST）、xlc の委任の担当が、main から作ったばかりのブランチで `git add docs/issues && git commit -q -m
"<件名 73 文字>" … && design-records check; echo rc=$?; …` を実行した。commit-msg の hook が「件名が 72 文字を超えています
(73 文字)」で拒んだが、`-q` と `;` のつなぎで失敗に気づかず、次の呼び出しの `git commit -q --amend -m …` が main の
マージコミット 4e9f726d8 を書き換えた a1a195361（親 2 つ）をブランチに作った。post-rewrite の `remap.commitRefs` は、issue の
本文の main のコミットの番号を a1a195361 に付け替えた。親のセッションが `reset --soft main` で 1 コミットに作り直した
（xlc main 63bbf7348 の第 2 親 a93780111）。

amend は新しいコミットを作るので main は変わらないが、ブランチの履歴の形と文書の番号が壊れる。一方、xlc にはマージの直後に
main の上でマージコミットの本文を amend で直した正当な例がある（reflog の 2026-10-21 02:02 と 02:05）。xlc には GitHub
リモートが無く、block-main-commit はそこでの main の commit を通す。

## 検討した案

- 案 1: 今のブランチが名前のある、既定ブランチでないブランチで、その先端が既定ブランチ（`git::default_branch`。
  guard-branch-base と同じ順で探す）に含まれる（`git merge-base --is-ancestor`）ときの `git commit --amend` を claude-hooks で
  止める。既定ブランチの上と detached HEAD（rebase の途中の edit）の amend、ブランチに固有のコミットがあるときの amend は通す
- 案 2: HEAD がマージコミットのときの amend を止める。既定ブランチの上の正当な amend（上の reflog）も止まり、fast-forward や
  squash でマージするリポジトリの既定ブランチのコミット（親 1 つ）は見逃す
- 案 3: 失敗を見落とす書き方（`git commit -q … ;`）を形で止める。今回の amend は別の呼び出しで、形からは見分けられない。
  `;` でつなぐ正当な形も多い
- 案 4: git の prepare-commit-msg の hook（第 2 引数 `commit` と第 3 引数のコミット）で amend を見分ける。githooks(5) は、
  `-m` / `-F` のときの第 2 引数を `message` と書き、`--amend -m`（今回の形）で `commit` になるかは確かめていない。
  リポジトリごとの hook の置き場（prek など）との重なりもある

## 決定と理由

案 1 を採る。守るものは既定ブランチのコミットがブランチで書き換えられないことで、それは先端が既定ブランチに含まれるかで
決まる。この状態で amend が正しい手順になる場面は無い（ブランチの最初のコミットは `git commit` で作り、既定ブランチの
コミットを直すなら既定ブランチの上で amend する）ので、block-main-commit や guard-git-stash と同じくエスケープは置かない
（ADR-0023 の形のエスケープは、外す理由がありうる検査のためのもの）。拒否の文言には、直前の `git commit` が拒まれていないかを
`git log -1` で確かめること、`git commit` で新しいコミットを作ること、既定ブランチのコミットを直すなら既定ブランチの上で
amend することを書く。

既定ブランチは `git::default_branch` の ref（origin があれば `origin/main` など）と、そのローカルのブランチの両方と比べる。
GitHub 以外の origin のリポジトリでは、/git-merge のマージが push されないまま、ローカルの main にだけある。

hook は実行前の状態しか見られない。同じコマンドの前に、同じディレクトリでブランチの先端か HEAD を動かしうる git の
コマンド（commit、switch、merge、rebase、pull、cherry-pick、revert、am、update-ref と、パスを渡さずに 1 つのコミットを指す
reset、ブランチを作る・切り離すか、パスを渡さずに `-`・コミット・作業ツリーに無い名前を指す checkout、`-f` の branch。
値の決まらない引数は指すものとして数える。サブシェルとコマンドの置き換えの中も）があれば止め、呼び出しを分けるよう示す。
パスを渡す reset と checkout（`git reset HEAD -- <path>` でステージから外すなど）は index と作業ツリーしか変えないので数えない。
既定ブランチの上で、前のコマンドがブランチを移らない（switch、checkout、rebase でない）なら、amend は既定ブランチの上のもの
（マージの直後に本文を直す）なので通す。既定ブランチが見つからないリポジトリでも、この検査は行う。amend が書き換えるコミットは前のコマンドの
成否と中身で決まり、書き方からは決められないため（ADR-0025 と同じく止める側に倒す）。`git commit -m a; git commit --amend` は
前の commit が拒まれれば既定ブランチのコミットを書き換え、`git switch -C <b> && …`、`git checkout -b <b> origin/main && …`、
`git reset --soft main && …` は先端を既定ブランチのコミットへ移す。分けた amend は、前のコマンドの後の状態で判定される。
`git commit -m a && git commit --amend` のように `&&` で成功が保証される形も止まるが、分ける 1 手で抜けられる。

拒否の文言の「既定ブランチの上で amend する」は、GitHub リモートの無いリポジトリでだけ示す。GitHub リモートがあれば
block-main-commit が既定ブランチの commit を止め、push 済みのコミットの書き換えは force push を要する。

最初の実装は、前の `git switch` / `checkout` をその先のブランチで判定し（guard-branch-base の `branch_at`）、ほかの前のコマンドは
見なかった。ローカルのレビュー（2026-10-30）が、既にあるブランチへの `git switch -C`、起点つきの `git checkout -b <b> origin/main`、
前の `git reset --soft` の後の amend が既定ブランチのコミットを書き換えるのに通ることを示したので、今の形にした。同じレビューで、
比べる先をローカルの既定ブランチにも広げ、`--no-am` などの略を `--no-amend` として読むようにした。2 周目のレビューが、パスだけの
`git reset` / `git checkout`、`git branch --show-current`、既定ブランチの上の `git merge … && git commit --amend` も止めることを
示したので、reset と checkout と branch は引数で見分け、既定ブランチに留まる形を通すようにした。3 周目のレビューが、その見分けが
値の決まらない引数（`$(git merge-base HEAD main)`）、`git checkout -`、`-qb`、リモートにだけあるブランチ名、既定ブランチの上の
`git rebase main <branch>` を通し、`git reset HEAD -- <path>` を止め、既定ブランチの無いリポジトリで検査を飛ばすことを示したので、
今の形にした。

### 帰結

- fetch していない古い追跡ブランチと、ローカルの既定ブランチのどちらにも無いコミット（ほかの clone が既定ブランチに入れた
  もの）を先端に持つブランチは見逃す
- `git -c alias.<名前>=` の alias と利用者の gitconfig の alias の amend、`$CMD` などの決められないコマンドの中の amend は見ない
- 同じコマンドで先端を動かした後の amend は、正当な形でも呼び出しを分ける手間がかかる

### 確認

- `.claude/tests/hooks.sh` の guard-git-amend の節（止める形と `-C` / `cd` / `env -C`、固有のコミット、既定ブランチの上と
  detached HEAD、`--amend` が値や pathspec の commit と `--no-am`、前に先端を動かしうるコマンドがあるときと数えない前のコマンド（パスだけの reset と checkout、既定ブランチの上の merge）、ローカルの既定ブランチにだけあるコミット、GitHub リモートのある origin/main との比較）
