---
status: accepted
date: 2026-10-11
requires: []
supersedes: [ADR-0010]
superseded-by:
issues: ["#268"]
---

# ADR-0011: system76-scheduler の除外を、実体の名前 nix で書く

## 背景

r995 は計算（xlc、OpenMC）に使う。時間を測る計算は `sbatch --exclusive` で流し、ほかの計算と重ならないようにしている。
一方、Nix のビルドは Slurm を通らない。r995 の `nix-daemon` が走らせるので、次のものがすべて計算と同時に CPU と I/O を使う。

- r995 自身の `nix-rebuild rebuild` と `update`（全ホストの検証ビルドを含む）
- 自動更新（`nix-auto-update`、無人）
- ノート PC（t14g4、x1ng1）から転送されるビルド（`max-jobs = 0` で r995 に投げる）

ビルドが計算の時間をどれだけ乱すかは測っていない。

デーモンのスケジューリングを idle にする（`nix.daemonCPUSchedPolicy` と `nix.daemonIOSchedClass`）と決めて反映したが、
実機で `nix-daemon` の主プロセスは `SCHED_OTHER` だった（unit の `CPUSchedulingPolicy=idle` は入っている）。
原因は COSMIC が有効にする system76-scheduler で、次のことを確かめた（issue #268）。

- idle の一時 unit で起動したプロセス（`nix-daemon --daemon`、`sleep`）は、約 1〜2 秒後に `SCHED_OTHER` になる。
  nix-daemon は `sched_set*` と `setpriority` を呼ばない（`strace -f` で 0 件）。スケジューラを止めると、idle のまま保たれる
- スケジューラの既定は `system-services`（`/system.slice/*`）に `nice=12 io="idle"` を与え、`sched=` が無いので OTHER に戻す。
  名前が c++、cargo、clang、cmake などのものは `batch`（`nice=19 sched="idle"`）にする
- 除外に一致したプロセスは、優先度を変えずに飛ばされる。**プロセスの名前は `/proc/<pid>/exe` の実体のファイル名**
  （スケジューラのソースの `process::name`）。nix-daemon は `nix` へのシンボリックリンクなので、名前は `nix-daemon`
  ではなく `nix` になる。名前を `nix-daemon` と書いた除外は一致せず、再起動した nix-daemon も `nice=12`、`SCHED_OTHER` だった

## 検討した案

- 案 1（採用）: `services.system76-scheduler.exceptions` に、名前 `nix` と `include descends="nix"` を入れる。
  ADR-0010 の方針（nix-daemon とその子孫を除外し、デーモンの idle をビルドまで伝える）を、実体の名前で書く
- 案 2: 除外を cmdline（実体のフルパス）で書く。パスにストアのハッシュとバージョンが入り、nix の更新のたびに外れるので採らない
- 案 3: `assignments` で、nix-daemon の配下に `sched="idle"` を与える。名前の問題は同じで、`system-services` との優先関係を
  確かめる手間も増える。案 1 で足りなければ検討する
- 案 4: 何もしない。nice 12 とコンパイラの idle で足りるとみなす。nice 12 は重みが小さいだけで、道を譲る保証ではない
- 案 5: system76-scheduler を r995 で無効にする。xlc など、ほかのプロセスの優先度管理（デスクトップの応答性）も失う。採らない

ADR-0005 の案 A（rebuild と update の全体を Slurm にする）と案 B（ビルドの段だけを Slurm にする）は、そこに書いた理由のまま
採らない。案 B は、この決定で足りなければ検討する。

## 決定と理由

案 1 にする（ユーザーの判断）。`hosts/r995/default.nix` に次を置く。計算のための機械なので r995 だけで、ノート PC には入れない。

- `nix.daemonCPUSchedPolicy = "idle"` と `nix.daemonIOSchedClass = "idle"`
- `services.system76-scheduler.exceptions = [ "nix" "include descends=\"nix\"" ]`

- **効果の範囲**: `SCHED_IDLE` は CPU ごとの優先度で、通常の優先度のタスクが動いている CPU でだけ、ビルドが道を譲る。
  計算が一部のコアしか使っていなければ、ビルドは空きコアで進む。メモリ帯域・キャッシュ・SMT の競合は残るので、
  厳密な時間測定の保証ではない（保証が要るなら案 B）
- **代償**: 全コアを使う計算の間は、rebuild と自動更新が遅くなる（全コアに通常の優先度のタスクがあれば止まる）。
  `nix-auto-update` は oneshot でタイムアウトが無く、待つだけで失敗しない
- **除外の範囲**: 名前 `nix` に一致するのは nix-daemon に限らず、`nix build` や `nix eval` などの nix のクライアントとその子孫も
  含む。クライアントはスケジューラの優先度の調整（`nice` など）を受けず、起動した側の方針のままになる。
  重い処理はデーモンの側で動くので、影響は小さいとみている

### 帰結

- nix-daemon とその子孫、nix のクライアントは、スケジューラの `nice=12`、`io="idle"`、`batch` の割り当ての対象外になる
- 除外はスケジューラが設定を読み込んだ後の新しいプロセスにだけ効く。反映後は nix-daemon の再起動が要る

### 確認

反映後に、r995 の実機で確かめる（issue #268）。

- nix-daemon を再起動し、主プロセスが数秒後も `SCHED_IDLE`（`chrt -p`）のままであること
- ビルドの最中に、子プロセス（bash、make、コンパイラ）が `SCHED_IDLE` を継いでいること（`ps -eo pid,cls,ni,comm`）。
  `descends="nix"` が sandbox 内のビルドプロセスにも及ぶかは、まだ見ていない
- ノート PC から `ssh-ng` で転送されたビルドにも効くか
- ビルドが計算の時間をどれだけ乱していたか、この設定で消えるか。xlc の計測を、ビルドの最中に流して比べる
