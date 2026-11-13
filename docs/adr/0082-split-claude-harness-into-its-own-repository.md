---
status: accepted
date: 2026-11-12
requires: []
supersedes: []
superseded-by:
issues: ["#677", "#688"]
---

# ADR-0082: Claude Code のハーネスを nixfiles から別のリポジトリに分け、flake input で取り込む

## 背景

nixfiles は、PC の設定（NixOS と home-manager）のリポジトリとして始まり、Claude Code のハーネス（グローバルの指示、スキル、
スクリプト、hook、それらが使う CLI とテスト）を `.claude/` と `modules/home/parts/` に足してきた。今は、変更の大半が
ハーネスである（数は 2026-11-11、main の f5869b3f）。

- 直近 300 コミットの表題のスコープで、PC の設定のもの（`flake`、`neovide`、`laptop`、`git`、`home`）は 19 件。
  多いのは `adr` 49、`claude-hooks` 41、`delegate` 34、`skills` 21、`scripts` 19 で、どれもハーネス
  （`git log -300 --format=%s` を数えた）
- `docs/adr/` の 79 件を表題で分けると、PC の設定が 9 件、Slurm が 12 件、ハーネスが 58 件
- ハーネスの Rust の CLI は 4 つ（`claude-hooks`、`commit-refs`、`design-records`、`history-rewrite`）で、`claude-hooks` だけで
  44 ファイル、うち Rust のソースが 37 ファイル、12,496 行

2 つのトピックが 1 つのリポジトリにあるので、次が起きている。

- PC の設定の履歴、ADR、issue が、ハーネスのものに埋もれる。開いている issue は 101 件
  （2026-11-11、`gh issue list --state open --limit 1000 --json number -q length`。この ADR の #677 を含む）
- PC の設定の変更にも、ハーネスの検査とテスト（flake の checks、pre-commit）がかかり、その逆もかかる
- nixfiles の `.claude/CLAUDE.md` はグローバルの指示の元なので、nixfiles に固有のプロジェクトの指示（ホストの構成、
  rebuild の手順）を置く場所が無い
- ハーネスの版と PC の設定の版が同じコミットで、片方だけを戻せない

自作のツールを別のリポジトリに置き、flake input で取り込む形は、`lsp-det` と `nucrawler` で使っている（`flake.nix`）。

## 決定の要因

- ハーネスの 1 つの変更（hook のルール、スキルの文、テスト）が、1 つのリポジトリの 1 つの PR に収まること
- 履歴、ADR、issue を、トピックごとに引けること
- スキルとスクリプトを直してから効くまでの速さが、今（`claude-sync`）より落ちないこと
- 移した先で、ファイルの履歴と、ADR どうしの参照を失わないこと
- nixfiles の履歴を書き換えないこと（各ホストの clone と、毎日の自動更新が main を追っている）

## 検討した案

- 案 A: 分けない
- 案 B: ハーネスを別のリポジトリに分け、nixfiles は flake input で取り込む
- 案 C: 同じリポジトリの中で、ハーネスを 1 つのディレクトリ（`harness/`）に集め、ADR も分ける
- 案 D: 文章（`.claude/` のスキル、スクリプト、CLAUDE.md）だけを別のリポジトリに分け、Rust の CLI と Nix のモジュールは
  nixfiles に残す

## 決定と理由

採用: 案 B。

### 境界

分ける線は「`.claude/` か Nix か」でなく、「開発の進め方のゲートとツールか、PC の構成か」に引く。hook のルールは Claude Code の
側（`claude-hooks`）と git の側（`git-hooks.nix` の pre-commit、commit-msg、pre-merge-commit）で同じ判定を共有していて
（`git-hooks.nix` の main へのコミットの例外は `block_main_commit.rs` と揃える、`ja-terms` の textlint は両方が呼ぶ）、
間に線を引くと 1 つの変更が 2 つのリポジトリにまたがる。

| 行き先               | 入れるもの                                                                                                                                                                                                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ハーネスのリポジトリ | `.claude/`（CLAUDE.md、スキル、スクリプト、テスト、README）、`claude-hooks`、`commit-refs`、`design-records`、`history-rewrite`、`ja-terms`、git の hook（`git-hooks.nix`、`staged-checks.sh`、`scan-staged-secrets.sh`）、`claude-sync.sh`、`claude-memory-backup.sh`、`claude-code.nix`、これらのテスト、ハーネスの ADR |
| nixfiles             | `hosts/`、`secrets/`、`modules/` の残り（git の利用者の設定の `git.nix`、`slurm/`、`cc-bar.nix`、Claude Code と Claude Desktop の本体を入れる `claude-apps.nix` を含む）、PC の設定の ADR、ハーネスの input                                                                                                               |

- ハーネスのリポジトリは flake で、home-manager のモジュールと、CLI のパッケージ、checks を出す。nixfiles は input に足して
  モジュールを import する。今 nixfiles が `claude-code.nix` に渡している値は 3 つで、どれもハーネスの内容なので、nixfiles からは
  渡さない。flake のソース（`claudeCodeSource = self`）はハーネスの flake の `self` になり、外部のスキル（`mattpocock-skills`）と
  `lsp-det` はハーネスの flake の input になる。Claude Code と Claude Desktop の本体のパッケージは、版を nixfiles の
  `flake.lock`（`llm-agents`）が決める PC の構成なので、nixfiles に残す
- Slurm は、投げる側（`slurm-run.sh`、`slurm-queue.sh`、`slurm-history.sh`、スキル、sbatch を止める hook）がハーネス、
  クラスタの構成（`modules/slurm/`、パーティション、優先度）が nixfiles。間の約束は、パーティションの名前（`main`、`timed`）、
  NFS の入口（`/mnt/r995/github`）、ログの置き場で、ハーネスの側の文書に書く
- ハーネスのリポジトリでも、グローバルの指示の元は `.claude/CLAUDE.md` に置き、ADR-0080 の設定（`claudeMdExcludes`）を
  そのまま持っていく。置き場を変えると ADR-0080 の案 A と同じ欠点（`~/.claude/CLAUDE.md` の無い環境で指示が読まれない、
  worktree で直した指示が同期まで効かない）が出る。nixfiles の `.claude/` は空き、プロジェクトの指示を置けるようになる

### 移し方

- 履歴: ハーネスのパスだけを残す形で nixfiles の履歴を書き換えたものを、新しいリポジトリの履歴にする。文書の中のコミットの
  番号は `commit-refs` で付け直す。nixfiles の側は履歴を書き換えず、移したファイルを通常のコミットで消す
- ADR: 番号を変えずに移し、両方のリポジトリで欠番を許す。ADR は、決定が扱うコードのある側に置く。置き場を、ADR どうしの
  参照が切れないことに合わせない（主役はコードで、記録のつながりのために置き場やツールを決めない）。切れるフロントマターの
  結びは、参照先の無い側で外す。本文の番号はそのまま残す
- issue: 開いているハーネスの issue を新しいリポジトリに移す。閉じた issue と、文書の中の issue の番号はそのまま残す
- リポジトリの名前、移す順序、切り替えの日の手順は、計画（`docs/plans/`）に書く

### 理由

- 案 B は、決定の要因のうち、変更が 1 つの PR に収まることと、トピックごとに引けることを満たす。境界を上の線に引けば、
  hook のルール、スキル、テストは同じリポジトリにある
- 速さの要因は、一部しか満たさない。文章とスクリプトを直してすぐ効かせる方法（`claude-sync` が store を経ずに
  手元の clone からコピーする）は残るが、既定のソース（`claude-sync.sh` の `~/nix/nixfiles`）をハーネスの clone に変える必要がある。ただし rebuild の activation も同じ同期を flake のソースから行い、ソースを正として上書きする
  （`claude-code.nix` の `claudeCodeSource`、`claude-sync.sh`）。今のソースは nixfiles 自身で、分けた後は lock が固定した
  ハーネスの input になる。lock がハーネスの main より古い間に rebuild すると、`~/.claude` の文章とスクリプトは lock の版に戻る。
  Rust の CLI と Nix のモジュールは、lock の更新と rebuild まで効かない。どちらも、ハーネスのマージの後に nixfiles の lock を
  進めれば揃う。lock は毎日 06:30 の自動更新（`modules/nix-auto-update.nix`）も進めるので、手で進めなくても翌日には揃う
- 案 A は、背景の 4 つがそのまま残る。ハーネスの変更の割合は増え続けている
- 案 C は、履歴、issue、検査の範囲、版の固定のどれも分かれない。分かれるのはディレクトリと ADR の置き場だけ
- 案 D は、いちばん多い種類の変更（hook のルールと、それを説明するスキルの文と、テスト）が 2 つのリポジトリの 2 つの PR に
  分かれる。スキルの文は hook の拒否メッセージと語を揃えていて、片方だけが先に入ると食い違う

分けても変わらないものもある。ほかのプロジェクトのセッションがハーネスの ADR を引けないこと（ADR-0046 の理由）と、
グローバルの指示の元のリポジトリで指示が 2 回読まれうること（ADR-0080 の理由）は、置き場が移るだけで残る。

### 帰結

- 良い点: PC の設定の履歴、ADR、issue が、PC の設定だけになる。ハーネスも同じ
- 良い点: nixfiles の `flake.lock` がハーネスの版を固定する。PC の設定を戻してもハーネスは戻らず、ハーネスだけを前の版に
  固定することもできる
- 良い点: nixfiles に、プロジェクトの指示（`.claude/CLAUDE.md`）を置ける
- 悪い点: ハーネスの変更は、効くまでが 2 段になる（ハーネスのマージ、nixfiles の lock の更新と rebuild）。文章とスクリプトは
  `claude-sync <ハーネスの clone>` ですぐ入るが、lock を進める前の rebuild で lock の版に戻る。lock は `nix-rebuild update` か
  毎日 06:30 の自動更新が進める。マージの前に試すには、文章とスクリプトは worktree から `claude-sync`、Rust の CLI は
  worktree でビルドしたバイナリをテストに渡す
- 悪い点: ハーネスのモジュールは、nixfiles の nixpkgs と home-manager で評価される。ハーネスの新しい版が、nixfiles の版に無い
  属性やオプションに頼ると、nixfiles の評価が失敗する。自動更新は全ホストの検証ビルドの失敗で lock を戻すので、壊れた構成は
  適用されない。ハーネスのテストは、ハーネスの `flake.lock` の nixpkgs でビルドした hook を確かめるので、配る hook の版と
  離れうる
- 悪い点: nixfiles の構成とハーネスのスクリプトの間に、名前と値の約束が残る（Slurm のパーティションの名前と NFS の入口、
  自動コミットの件名、rebuild する構成の目印の `nix-rebuild.sh`）。`modules/home/parts/tests/harness-contract.sh` が
  突き合わせる。ただし目印は、こちらにファイルがあるかだけを確かめ、ハーネスの側の値とは照らさない（ハーネスの
  post-merge-cleanup が Rust に移り、値は claude-hooks のソースの文字列になった。照らす方式は補足の 2026-11-14 の項）
- 外部のスキルと `lsp-det` の版は、nixfiles の `flake.lock` が決めるままにした（ハーネスの input を nixfiles の input に
  follows する）。毎日の自動更新が進める。ハーネスの `flake.lock` のそれらは、ハーネスのテストにだけ使う
- 切り出したのは 2026-11-12、nixfiles の f02b191e。3916 コミットのうち 2752 件が `tagawa0525/claude-harness` の履歴に
  なった。`claude-code.nix` を `development.nix` から切り出す前の 1 か月分（2026-01-12 から 02-20）は、nixfiles の履歴にだけ
  残る。nixfiles の履歴は書き換えていない
- 残り（#677）: 開いているハーネスの issue を新しいリポジトリに移す。t14g4 と x1ng1 で `~/nix/claude-harness` を clone する

### 確認

- ハーネスのリポジトリで `nix flake check` と、`.claude/tests/`、`modules/home/parts/tests/` のテストがすべて通る
  （2026-11-12、tagawa0525/claude-harness#2 の時点。切り出す前から失敗していた 2 本は同じ PR で直した）
- 切り替えの前後で、r995、t14g4、x1ng1 の構成の、4 つの hook の本文、`home.packages` の名前、`home.file` と
  `xdg.configFile` のキー、`programs.git.settings` が、store の hash を除いて同じ。`claudeCodeSetup` の activation の差は、
  消した分岐のコメント 1 行（2026-11-12、`nix eval` で比較）
- nixfiles の `git ls-files` に、境界の表でハーネスに入れたパスが残っていない
- 両方のリポジトリで `design-records check` が通る
- `modules/home/parts/tests/harness-contract.sh` が通る

## 補足

- 2026-11-14: ハーネスの post-merge-cleanup が Rust（`claude-hooks script post-merge-cleanup`）に移り、`harness-contract.sh`
  が sh の本文に目印を見つけられず、`nix-rebuild update` が止まった。Rust のソースから引用符で囲んだ目印のパスを探す照合を
  試したが、ファイルの分割、定数への切り出し、パスの組み立てのような挙動を変えない直しで毎日の自動更新が止まるので捨て、
  こちらにファイルがあるかだけを確かめる。ハーネスのテストの目印も同じ値を固定で持つので、ハーネスの側で値を変えたときの
  食い違いはどちらのテストも捕まえない。ロックした版の claude-hooks を動かして確かめる方式は #688 に書いた
