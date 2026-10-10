---
status: accepted
date: 2026-10-11
requires: []
supersedes: [ADR-0005]
superseded-by:
issues: ["#268"]
---

# ADR-0010: nix-daemon とその子孫を system76-scheduler の対象から外し、idle の優先度を保つ

## 背景

r995 は計算（xlc、OpenMC）に使う。時間を測る計算は `sbatch --exclusive` で流し、ほかの計算と重ならないようにしている。
一方、Nix のビルドは Slurm を通らない。r995 の `nix-daemon` が走らせるので、次のものがすべて計算と同時に CPU と I/O を使う。

- r995 自身の `nix-rebuild rebuild` と `update`（全ホストの検証ビルドを含む）
- 自動更新（`nix-auto-update`、無人）
- ノート PC（t14g4、x1ng1）から転送されるビルド（`max-jobs = 0` で r995 に投げる）

ビルドが計算の時間をどれだけ乱すかは測っていない。

ADR-0005 で、デーモンのスケジューリングを idle にする（`nix.daemonCPUSchedPolicy` と `nix.daemonIOSchedClass`）と決め、
2026-10-11 に r995 へ反映した。ところが反映後の実機で、`nix-daemon` の主プロセスは `SCHED_OTHER` だった（unit の
`CPUSchedulingPolicy=idle` は入っている）。原因は COSMIC が有効にする `system76-scheduler` だった（issue #268 のコメント）。

- idle の一時 unit で `nix-daemon --daemon` を起動すると、policy が約 1.5〜2 秒後に idle から OTHER に変わる。
  `nix-daemon` は `sched_set*` と `setpriority` を呼ばない（`strace -f` で 0 件）
- idle の一時 unit で `sleep` を起動しても、約 1 秒後に OTHER になる。nix に固有の挙動ではない
- `system76-scheduler` は execsnoop で新しいプロセスを監視する。既定の `system-services`（`/system.slice/*`）は
  `nice=12 io="idle"` で `sched=` が無く、OTHER に戻す。名前が c++、cargo、clang、cmake などに一致するものは
  `batch`（`nice=19 sched="idle"`）にする。`package-manager` に nix は無い

つまり ADR-0005 の設定は、起動の 1〜2 秒後に上書きされ、ビルドの子プロセスにも伝わらなかった。
コンパイラ（名前が `batch` に一致するもの）は idle になるが、bash や make などは nice 12 の OTHER になる。

## 検討した案

- 案 1（採用）: `services.system76-scheduler.exceptions` に `nix-daemon` と、その子孫（`include descends="nix-daemon"`）を入れて、
  スケジューラに触らせない。ADR-0005 の設定がそのままビルドの子プロセスまで伝わる。r995 だけに入れる
- 案 2: `services.system76-scheduler.assignments` で、nix-daemon の配下に `sched="idle"` を与える。スケジューラの規則に
  乗せられるが、子プロセスごとに規則が一致する必要があり、`system-services` との優先関係を確かめる手間が増える。
  案 1 で足りなければ検討する
- 案 3: 何もしない。nice 12 とコンパイラの idle で足りるとみなす。nice 12 は重みが小さいだけで、道を譲る保証ではなく、
  ADR-0005 の「通常の優先度のタスクが動く CPU ではビルドが譲る」がコンパイラ以外では成り立たない
- 案 4: `system76-scheduler` を r995 で無効にする。xlc など、ほかのプロセスの優先度管理（デスクトップの応答性）も失う。
  採らない

ADR-0005 の案 A（rebuild と update の全体を Slurm にする）と案 B（ビルドの段だけを Slurm にする）は、そこに書いた理由のまま
採らない。案 B は、この決定で足りなければ検討する。

## 決定と理由

案 1 にする（ユーザーの判断）。`hosts/r995/default.nix` に次を置く。

- `nix.daemonCPUSchedPolicy = "idle"` と `nix.daemonIOSchedClass = "idle"`（ADR-0005 から引き継ぐ）
- `services.system76-scheduler.exceptions = [ "nix-daemon" "include descends=\"nix-daemon\"" ]`

計算のための機械なので r995 だけに入れ、ノート PC には入れない（ノート PC の手元のビルドを遅くする理由が無い）。
除外の範囲を nix-daemon の配下に絞るので、xlc などほかのプロセスはスケジューラの管理のままになる。

- **効果の範囲**: `SCHED_IDLE` は CPU ごとの優先度で、通常の優先度のタスクが動いている CPU でだけ、ビルドが道を譲る。
  計算が一部のコアしか使っていなければ、ビルドは空きコアで進む。メモリ帯域・キャッシュ・SMT の競合は残るので、
  厳密な時間測定の保証ではない（保証が要るなら ADR-0005 の案 B）
- **代償**: 全コアを使う計算の間は、rebuild と自動更新が遅くなる（全コアに通常の優先度のタスクがあれば止まる）。
  `nix-auto-update` は oneshot でタイムアウトが無く、待つだけで失敗しない

### 帰結

- nix-daemon の配下は、スケジューラの `nice=12`、`io="idle"`、コンパイラの `batch` 割り当ての対象外になる。
  daemon の idle をそのまま継ぐ（確認の項を参照）
- ADR-0005 の `nix.daemon*` の設定は、この決定に含めて引き継ぎ、ADR-0005 は置き換え済みにする

### 確認

反映後に、r995 の実機で確かめる（issue #268）。

- 起動の数秒後も `nix-daemon` の主プロセスが `SCHED_IDLE`（`chrt -p`）のままであること
- ビルドの最中に、子プロセス（bash、make、コンパイラ）が `SCHED_IDLE` を継いでいること（`ps -eo pid,cls,ni,comm`）
- ノート PC から `ssh-ng` で転送されたビルドにも効くか（`nix-daemon --stdio` が本体のデーモンに中継するなら効く）
- ビルドが計算の時間をどれだけ乱していたか、この設定で消えるか。xlc の計測を、ビルドの最中に流して比べる

## 補足

- 2026-10-11: 設定の効きの確認は、反映後に issue #268 で行う。`descends` の一致が sandbox 内のビルドプロセスに及ぶかは、まだ実機で見ていない
- 2026-10-11: 原因が system76-scheduler であることは、スケジューラを止めると idle が保たれる試験で確定した。
  最初の除外（`nix-daemon`）は一致していなかった。スケジューラは `/proc/<pid>/exe` の実体のファイル名で識別し、
  nix-daemon の実体は `nix` なので、除外を `nix` と `include descends="nix"` に直した。`nix` の名前で除外されるのは
  nix のクライアントも同じで、スケジューラがそれらに与える優先度を失う（影響は小さいとみている）
