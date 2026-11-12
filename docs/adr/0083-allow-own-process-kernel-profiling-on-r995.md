---
status: accepted
date: 2026-11-12
requires: []
supersedes: []
superseded-by:
issues: ["#685"]
---

# ADR-0083: r995 で、利用者が自分のプロセスのカーネル側を perf で記録できるよう、perf_event_paranoid を 1、kptr_restrict を 0 にする

## 背景

r995 は tagawa が 1 人で使う計算用の機械（デスクトップを兼ねる）で、Slurm のジョブも tagawa で走る。人のアカウントは tagawa だけで、
ほかはサービスのアカウントと `nixbld*` のビルドのアカウント（コンテナの中も含む）。

xlc の性能の測定で、カーネル側を含む呼び出しの連鎖つきの記録（`perf record -g`）が失敗した。2026-11-12 の r995（カーネル 7.3.1）の値は `kernel.perf_event_paranoid = 2`
（カーネルの既定）、`kernel.kptr_restrict = 1`（NixOS の `nixos/modules/config/sysctl.nix` が `mkDefault 1` で入れる）で、
利用者側だけの記録（`perf stat -e cycles:u`、`perf record -e cycles:u --user-callchains -g`）は動く。xlc の自己遮蔽のジョブは
32 スレッドで利用者側の CPU 4 時間 27 分に対してカーネル側が 7 分 19 秒あり、59 GB を確保するので、ページフォルトとロックの
待ち（futex）がどこで起きているかを見たい。ユーザーは、設定の変更が要るなら行って、より多くの情報を得てよいと認めた
（ユーザー 2026-11-12）。

### 各値で利用者（CAP_PERFMON なし）に許されること

出典は Linux v7.3 の `Documentation/admin-guide/sysctl/kernel.rst`（perf_event_paranoid、kptr_restrict）、
`Documentation/admin-guide/perf-security.rst`（Unprivileged users、Privileged Perf users groups）と、次のソース。

| `perf_event_paranoid` | 許されること                                                                                                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2                     | 自分のプロセスの、利用者側で起きた事象だけ。`perf_event_open` は `exclude_kernel` が無いか、カーネル側の呼び出しの連鎖を求めると `perf_allow_kernel()` で `EACCES`（`kernel/events/core.c`） |
| 1                     | 自分のプロセスの、カーネル側を含む事象と呼び出しの連鎖。CPU ごと（システム全体）の記録は不可（`perf_allow_cpu()`）                                                                           |
| 0                     | 加えて、システム全体（`perf record -a`、`perf top`）。raw のトレースポイントと ftrace の function は不可                                                                                     |
| -1                    | 加えて、raw のトレースポイントのデータと ftrace の function。`perf_event_mlock_kb` の上限も外れる                                                                                            |

- トレースポイントの raw のデータ（`perf trace` などが読む）は、プロセスに付けた記録でイベントが `TRACE_EVENT_FL_CAP_ANY`
  （システムコールの入口と出口、uprobe など）なら paranoid の確認なしに許され、ほかのイベント（`sched:*` など）は -1 か
  CAP_PERFMON が要る（`kernel/trace/trace_event_perf.c` の `perf_trace_event_perm`）。この判定は paranoid 1 と 2 で変わらない
- paranoid 1 で開くのは、`perf_allow_kernel()` だけが守るもの全部で、カーネル側の事象と呼び出しの連鎖のほかに、物理アドレスの
  サンプル（`PERF_SAMPLE_PHYS_ADDR`）、カーネルの分岐の記録（`PERF_SAMPLE_BRANCH_KERNEL` など）、PMU の raw のサンプルの物理アドレス
  （r995 の AMD の IBS は、`perf_allow_kernel()` が失敗したときだけ消す）などがある（`kernel/events/core.c` の `perf_copy_attr` と
  `perf_event_open`、`arch/x86/events/amd/ibs.c` の `perf_ibs_phyaddr_clear`。網羅ではない）
- カーネルのシンボル名は、perf が `/proc/kallsyms` のアドレスから引く。アドレスが見えるのは `kallsyms_show_value()`
  （`kernel/ksyms_common.c`）が真のときで、kptr_restrict が 0 かつ paranoid が 1 以下（資格を見ない）、または CAP_SYSLOG を
  持つとき。paranoid が 1 以下ならカーネル側のサンプルの IP（カーネルのアドレスそのもの）が利用者に渡るので、カーネルは
  kallsyms の公開をこの条件に結んでいる（同じファイルの注釈）。
  kptr_restrict が 1 のままでは、paranoid を下げてもアドレスが 0 になり、カーネルのサンプルに名前が付かない。
  kptr_restrict が 0 のとき `%pK` はハッシュした値を出す（kernel.rst）。生のアドレスは、paranoid 1 で開く perf のサンプル（上の項）と、
  `kallsyms_show_value()` が守るもの（`/proc/kallsyms`、`/proc/modules` など）に出る
- CAP_PERFMON を持つプロセスは paranoid の制限を受けない（perf-security.rst。`perf_allow_kernel()`、`perf_allow_cpu()`、
  `perf_allow_tracepoint()` は、paranoid が制限する値でも `perfmon_capable()` なら通す）。kptr_restrict が 1 でも、CAP_SYSLOG を持てば `/proc/kallsyms` のアドレスが見える
- トレースポイントのイベントの名前から番号を引くには、tracefs（`/sys/kernel/tracing`）が読める必要がある。r995 では
  `root:root` の `0700` で、利用者は読めない（2026-11-12 に `ls -ld` で確認）

## 検討した案

- 案 1（採用）: sysctl で `kernel.perf_event_paranoid = 1`、`kernel.kptr_restrict = 0` にする。要る情報（自分のジョブのカーネル側の
  サンプル、呼び出しの連鎖、シンボル名、ページフォルトとコンテキストスイッチの事象）が取れる最も高い paranoid の値。解析の対象は
  呼び出した環境のまま走り、どの perf の実行ファイルでも、どの文脈（Slurm のジョブ、sandbox の中）でも効く。sysctl は資格を見ずに
  r995 のすべてのプロセスに効く（範囲は「決定と理由」の「緩める範囲」）
- 案 2: paranoid を 0 か -1 にする。案 1 に加え、システム全体の記録と raw のトレースポイント（`sched:*` など）まで全アカウントに
  許す。ジョブの解析は `perf record -- <コマンド>` か `-p <pid>` のプロセスに付けた記録で足りるので、採らない
- 案 3: sysctl を変えず、NixOS の `security.wrappers` で perf に `cap_perfmon,cap_syslog` を付け、ラッパーを `perf` group（tagawa
  だけ）に限る（perf-security.rst の Privileged Perf users groups の方法）。次の理由で採らない（出典は nixpkgs の
  `nixos/modules/security/wrappers/wrapper.c` と `default.nix`）
  - ラッパーは実行の前に glibc の危険な環境変数（`LD_LIBRARY_PATH`、`LD_PRELOAD`、`TMPDIR`、`GLIBC_TUNABLES`、`MALLOC_ARENA_MAX`
    などの `MALLOC_*`）を消す。`perf record -- <コマンド>` で起動した解析の対象は、本番と違う環境で走る。ページフォルトとロックの
    待ちを見たいジョブで、確保の設定（`MALLOC_*`、`GLIBC_TUNABLES`）が変わると、測るものが変わる
  - capability を ambient の集合に上げてから実行するので、解析の対象とその子孫のすべてが CAP_PERFMON（システム全体の記録を
    含む）と CAP_SYSLOG を持つ。緩める範囲は、案 1 より広い権限を、perf の下で走るもの（NJOY、OpenMC、Python のパッケージを
    含む）に渡す形に変わるだけで、危険が小さくなるとは言えない
  - no_new_privs の文脈（bubblewrap などの sandbox、`NoNewPrivileges=` の unit）ではファイルの capability が効かず、ラッパーは
    ambient に上げられずに終了コード 1 で止まる。PATH で前にあるラッパーが失敗するので、今は動く利用者側だけの perf も使えなくなる
  - group の所属は新しいログインからしか効かない。r995 の tagawa は `linger = true` で、systemd のユーザーの manager とその下の
    プロセスは再起動まで perf group を持たず、PATH の検索は実行できないラッパーを飛ばして capability の無い perf を黙って使う
  - 経緯: 初めは案 1 を選び、ローカルのレビューで、全アカウントに効くことを書いていないと指摘されて案 3 に替えた。案 3 の
    レビューで上の環境変数と no_new_privs の問題が見つかり（wrapper.c で確かめた）、案 1 に戻した
- 案 4: tracefs を利用者が読めるようにする（マウントの `gid=`、`mode=`）。`perf trace -s` でシステムコールの時間の集計が取れるが、
  tracefs の全体（`trace`、`trace_pipe` のカーネルのトレースの中身を含む）を読めるようにする。futex の待ちの場所はコンテキスト
  スイッチの事象を呼び出しの連鎖つきで記録すれば見え（`perf record -e context-switches -g`）、回数と時間は
  `strace -f -c -e trace=futex` で取れるので、今は採らない。`perf trace` が要る場面が出たら、そのときに足す

## 決定と理由

案 1 にする。`hosts/r995/default.nix` に `boot.kernel.sysctl` の 2 つの値を置く。ほかのホスト（t14g4、x1ng1）は変えない。

- **緩める範囲**: r995 のすべてのプロセス（どのアカウントでも、コンテナと sandbox の中でも、seccomp などで別に止めていなければ）が、
  自分のプロセスについて、`perf_allow_kernel()` だけが守るもの（背景の項。カーネル側の事象と呼び出しの連鎖、物理アドレス
  など）を記録でき、`kallsyms_show_value()` が守るカーネルのアドレスを読める。個々のアカウントと開くものは列挙しない（範囲は
  2 つの関数の判定で決まり、列挙は漏れる）
- **受け入れる理由**: これは外から r995 に入る入口を増やさない。外から届くもの（sshd、avahi、Tailscale の内側のサービス、
  デスクトップで扱う外の入力など）は変わらない。増えるのは、どれかのプロセスを乗っ取った者がカーネルの権限に上がるときの
  手がかり（KASLR の配置、物理アドレスなど）と、カーネル側の `perf_event_open` という局所的な攻撃面。ユーザーは、r995 が 1 人で使う計算用の機械であることを前提に、
  要る情報を得る変更を認めた（ユーザー 2026-11-12）。ほかの人のアカウントを足すか、r995 を共用にするときは見直す
- システム全体の記録と、`TRACE_EVENT_FL_CAP_ANY` でない raw のトレースポイントは、今までどおり CAP_PERFMON（root を含む）だけ

### 帰結

- カーネル側を含む `perf record -g` と、`perf report` でのカーネルのシンボル名が、利用者の権限（Slurm のジョブを含む）で使える
- 解析の対象は、呼び出したシェルやジョブの環境変数のまま走る
- `perf trace` と、トレースポイント（`syscalls:*`、`sched:*`）を名前で指定する記録は、tracefs が読めないので使えないままの見込み
  （案 4。実機では確かめていない）
- 値は `systemd-sysctl` が適用する。rebuild で切り替われば、再起動しなくても効く

### 確認

rebuild の後に、r995 の実機で利用者の権限で確かめる（issue #685）。

- `sysctl kernel.perf_event_paranoid kernel.kptr_restrict` が 1 と 0
- `perf record -e cycles -g -o <一時ファイル> -- sleep 0.2` が成功し、`perf report -i <一時ファイル> --stdio --sort sym` に
  カーネルのシンボル名（`[k]` の行）が出る
- `perf stat -e page-faults,minor-faults,major-faults,context-switches,cpu-migrations -- sleep 0.2` が権限のエラーなく数える
- `perf record -a -o <一時ファイル> -- sleep 0.2` が権限のエラーで止まる（paranoid 1 の範囲の外）
- Slurm のジョブの中で `perf record -e cycles -g -- sleep 0.2` が成功する
- 受け入れた範囲の確認: tagawa の外のアカウントで、`sudo -u nobody head -1 /proc/kallsyms` のアドレスが 0 でなく、
  `sudo -u nobody perf stat -e cycles:k -- true` が数える
- `perf trace -s -- sleep 0.2` が tracefs の権限で止まるか（帰結の見込みのとおりか）
