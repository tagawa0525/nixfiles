# x1ng1: 電源管理・バッテリー調査メモ

ThinkPad X1 Nano (1st Gen) の電源まわりを実測した記録 (2026-07-28、2026-08-01 追記)。

「蓋を閉じている間の電池の減りが大きい」「充電上限 80% にしたはずが 100% になっている」という 2 つの疑問を起点に調査した。**結論として、いずれもソフトウェア設定の不具合ではなく機体の仕様上の挙動だった。**同じ検討を繰り返さないために経緯を残す。

後日 (2026-08-01)「蓋を開けたまま放置したら急激に減った」という別の事象が発生し、こちらは**上流 cosmic-idle のバグ**だった。機体の仕様と切り分けるため同じ文書にまとめる。

## 要約

| 項目                             | 結論                                                     |
| -------------------------------- | -------------------------------------------------------- |
| サスペンド中の消費               | 299 mW (約 15%/日)。S0ix に正常に入れており改善余地なし  |
| hibernate                        | **この機体では動作しない**。デバイス凍結段階でハング     |
| BIOS の S3 有効化                | 可能だが消費が悪化する (413 mW)。**使わない**            |
| 充電閾値が 100% になる件         | EC の揮発性設定のため。電源オフ中は保持されない          |
| バッテリー時に自動サスペンドせず | **cosmic-idle のバグ**。overlay でパッチを当てて対処済み |

## 実測値

| 状態                   | 消費電力   | 満充電 (47.66 Wh) からの持続 |
| ---------------------- | ---------- | ---------------------------- |
| 稼働中 (通常作業)      | 約 4.0 W   | 約 11〜12 時間               |
| サスペンド (s2idle)    | **299 mW** | 約 6.6 日                    |
| サスペンド (S3 / deep) | 413 mW     | 約 4.8 日                    |

サスペンド時は S0ix 滞在率 98.9% で、ほぼ全時間を最深の省電力状態で過ごしている。**誤起床も発生していない** (`PM: suspend entry` と `exit` がきれいにペアになる)。つまり s2idle として最適な状態であり、0.3 W はこの機体の下限。

## 蓋を閉じると 1 日あたり約 15% 減る

本機は **S3 非対応 (Modern Standby 専用機)** で、BIOS 既定では `s2idle` しか選べない。

```console
$ cat /sys/power/mem_sleep
[s2idle]
```

S3 なら 1〜2%/日 で済むところ、s2idle では `0.3 W × 24 h = 7.2 Wh` = 満充電の約 15% を消費する。これは故障でも設定ミスでもない。

## バッテリー駆動でも自動サスペンドしない (cosmic-idle のバグ)

2026-08-01、蓋を開けたまま放置したら 17% まで減っていた。**消費が異常だったのではなく、7 時間 15 分ものあいだ一度もサスペンドしなかった**のが原因。

### 観測された事実

`/var/lib/upower/history-charge-*.dat` と journal から再構成した推移。

| 時刻        | 残量 | 状態                             |
| ----------- | ---- | -------------------------------- |
| 07/31 02:50 | 75%  | 放電中                           |
| 07/31 02:51 | —    | 蓋を閉じてサスペンド (s2idle)    |
| 08/01 08:38 | 60%  | 復帰 (29 時間 47 分のサスペンド) |
| 08/01 15:53 | 17%  | 放電中。この間ずっと起きたまま   |

- **サスペンド中の消費は正常**。29.8 h で 15 ポイント = 約 7.1 Wh → **237 mW**。上記の実測値 299 mW と整合する
- **稼働中の消費も正常**。7.24 h で 43 ポイント = 約 20.3 Wh → 平均 2.8 W。うち 09:32 (51%) → 09:40 (41%) の急落は残量計の再校正とみられ、除くと 2.15 W でアイドル相当
- 7/30 08:04 の起動以降、**アイドルによる自動サスペンドは一度も発生していない** (`PM: suspend entry` は 7/31 02:51 の蓋閉じ由来の 1 回のみ)
- 一方で**画面オフとロックは機能していた** (15:55 に keyring unlock の記録)

つまり「アイドル検知は生きているのにサスペンドだけ発火しない」という状態だった。

### 根本原因

`cosmic-idle` はサスペンド用の idle notification を `recreate_notifications()` でしか生成せず、その呼び出しは **起動時・設定変更時・screensaver inhibit の変化時**の 3 つに限られる。UPower の `OnBattery` 変化を処理する `handle_event()` はフィールドを更新するだけで再作成しない。

```rust
// src/main.rs
fn handle_event(&mut self, event: Event) {
    match event {
        Event::OnBattery(value) => {
            self.on_battery = value;          // recreate_notifications() を呼ばない
        }
        Event::ScreensaverInhibit(value) => {
            self.screensaver_inhibit = value;
            self.recreate_notifications();    // こちらは呼ぶ
        }
    }
}
```

`recreate_notifications()` 内でサスペンド時間を決める分岐は次のとおり。

```rust
let suspend_time = if self.screensaver_inhibit { None }
    else if self.on_battery { self.conf.suspend_on_battery_time }
    else { self.conf.suspend_on_ac_time };
```

`on_battery` の初期値は `false` (AC 扱い) で、COSMIC 設定の「コンセント接続時の自動サスペンド」を**しない** (= `None`) にしていたため、**起動時に notification が一度も作られず、以後 AC を抜いても永久に発火しない**状態で固定された。

`screen_off_time` は `on_battery` に依存しないため画面オフとロックだけは動く。観測事実と完全に一致する。

裏付けとして、cosmic-idle の起動は 7/30 08:04:18、その 4 秒前の電源状態は `pending-charge` (= AC 接続中)。08:29 に放電へ移行したが反映されていない。

なお COSMIC 設定の「低バッテリー時の自動サスペンド」は原文 *Automatic suspend on battery* の訳で、**残量ではなくバッテリー駆動時**の意味。

### 上流の状況 (2026-08-01 時点)

アップグレードでは直らない。

| 参照          | コミット   |
| ------------- | ---------- |
| `epoch-1.5.0` | `c95d066b` |
| `epoch-1.4.0` | `c95d066b` |
| master HEAD   | `c95d066b` |

最新タグ・nixpkgs が使うタグ・master がすべて同一コミットを指す (`epoch-*` は COSMIC のリリース列に合わせて各リポジトリへ一斉に打たれるタグで、当該リポジトリに変更がなくても増える)。コード実体の最終更新は 2025-10-05 の `chore: update dependencies` で、修正 PR も存在しない。

### 対処

`modules/cosmic-idle-fix.nix` の overlay で 1 行パッチを当てている (`modules/patches/`)。

```rust
Event::OnBattery(value) => {
    self.on_battery = value;
    self.recreate_notifications();
}
```

`Cargo.lock` は変わらないので `cargoHash` の追従は不要、再ビルドも末端バイナリ 1 個で済む。

あわせて DE に依存しない防波堤として UPower の低残量アクションを `modules/profiles/laptop.nix` に設定した。

| 設定                  | 値         | 理由                                                                |
| --------------------- | ---------- | ------------------------------------------------------------------- |
| `criticalPowerAction` | `PowerOff` | 既定の `HybridSleep` は hibernate がハングして使えない              |
| `percentageCritical`  | `10`       | 既定の 5 は `percentageAction` と同値で警告が機能しない             |
| `percentageAction`    | `5`        | 停止に要するのは 0.2% 程度だが、残量計の再校正誤差 (10 pt) に備える |

`Suspend` を選ばなかったのは、サスペンドしても放電 (0.3 W) が止まらず約 15 時間で完全放電し、結局は汚い電源断になるため。NixOS も `allowRiskyCriticalPowerAction` を要求して assertion で止めてくる。

**「10% でサスペンドし 2% で電源を切る」という 2 段構えは標準機能では組めない。**サスペンド中は UPower 自身が停止しており残量を監視する主体がいないため。RTC アラームで定期的に起床して判定する仕組みを自作すれば可能だが (本機に `/sys/class/rtc/rtc0/wakealarm` は存在する)、cosmic-idle の修正で低残量まで落ちる状況自体が起きにくくなるため見送った。

### 検証方法

パッチの効きは、**AC を抜いた状態で設定を変更しても直ることはない**点で確認できる (設定変更は `recreate_notifications()` を呼ぶので、パッチなしでも一時的に復活してしまう)。素直に次で確認する。

1. `~/.config/cosmic/com.system76.CosmicIdle/v1/suspend_on_battery_time` を短くする (例: `Some(60000)` = 1 分)
2. **AC を接続したまま**セッションを再ログインし、cosmic-idle を起動時 AC 状態にする
3. AC を抜いて放置する
4. 1 分でサスペンドすれば OK (パッチ前は永久にサスペンドしない)
5. 確認後、`suspend_on_battery_time` を元に戻す

## hibernate は動作しない

消費をゼロにするため `suspend-then-hibernate` の導入を試みたが、**hibernate 自体が動かないため断念した** (PR #102 は破棄)。

### 症状

4 回試行し、いずれも同じ段階で停止した。

```text
PM: hibernation: hibernation entry
（デバイス凍結段階で停止）
```

再起動後に `swap USED = 0B` / `Unable to resume from device` となっており、**イメージの書き込みに一切到達していない**。

なお `hibernation entry` の直後に journald も凍結されるため、**ログの最終行は停止箇所を示さない**。実際、最終行に現れる `wwan wwan0: port ... disconnected` は犯人ではなかった (下記のとおり unbind しても停止箇所は変わらない)。

### 試して解決しなかったこと

| 試行                                           | 結果                                     |
| ---------------------------------------------- | ---------------------------------------- |
| そのまま `systemctl hibernate`                 | ハング (画面が戻り操作不能)              |
| `iosm` (LTE モデム) を PCI unbind してから実行 | ハング。停止箇所は変わらず               |
| `pm_test = devices` による切り分け             | ハング。**デバイス凍結段階の問題と確定** |
| BIOS を `Linux S3` に変更して実行              | ハング。ACPI が S3 を申告しても変化なし  |

### 前提条件は満たしていた

以下はすべて充足しており、**これらは必要条件にすぎず実機での動作を保証しない**。

- swap 16 GB > RAM 15 GiB
- `boot.resumeDevice` 設定済み (`modules/boot-lanzaboote.nix`)
- `/sys/power/state` に `disk` あり
- カーネル lockdown 無効 (Secure Boot 下でも hibernate 自体は許可される)
- ACPI が S4 を申告 (`supports S0 S4 S5`)

### 未解明の点

どのデバイスが凍結に失敗するかは特定できていない。追う場合は TTY に切り替え、コンソールの suspend を無効化して停止箇所を目視する。

```console
$ sudo sh -c 'echo 8 > /proc/sys/kernel/printk; \
    echo N > /sys/module/printk/parameters/console_suspend; \
    echo 1 > /sys/power/pm_print_times; \
    echo devices > /sys/power/pm_test; \
    echo disk > /sys/power/state'
```

画面に流れる最後のデバイスが犯人。ただし**得られる利益 (長時間放置時の 15%/日) に対してハングを伴う調査コストが見合わないと判断し、ここで打ち切った**。

## BIOS の S3 有効化は逆効果

BIOS の `Config → Power → Sleep State` を `Linux S3` にすると S3 が使えるようになる。

```console
$ cat /sys/power/mem_sleep
s2idle [deep]
$ journalctl -b | grep "supports S"
ACPI: PM: (supports S0 S3 S4 S5)
```

S3 への移行・復帰は正常に動作した (`PM: suspend entry (deep)`) が、**消費電力は 299 mW → 413 mW と 38% 悪化した**。Modern Standby 前提の設計に S3 を後付けした結果、一部デバイスの電源管理が働かなくなったと考えられる。

**BIOS は既定の `Windows and Linux` のままにすること。**

## 充電閾値が 100% になることがある

`services.tlp.settings` の充電閾値 (75/80) は正しく機能しているが、**natacpi (thinkpad_acpi) 経由で設定される EC の揮発性設定であり、電源オフ中は保持されない**。

そのため次の経路で 100% まで充電される。

1. AC を接続したままシャットダウン
2. EC の閾値が失われ、既定値 (96/100) で **100% まで充電される**
3. 次回起動時に TLP が 75/80 を再設定する
4. しかし閾値は「上限を超えたら充電を止める」だけで、**超過分を放電させる機能はない**
5. AC を挿したままだと 100% に張り付いたまま残る

### 見分け方

`energy_full` と `energy_now` が一致し、かつ `energy_full_design` に近い値なら本当に満充電されている。

```console
$ cd /sys/class/power_supply/BAT0 && grep . energy_now energy_full energy_full_design
energy_now:47660000
energy_full:47660000
energy_full_design:48280000
```

`tlp-stat -b` も同じ診断を返す (`BAT0 charge level is above the stop threshold`)。

### 解消方法

**一度 STOP 閾値 (80%) を下回るまで放電させる**しかない。AC を抜いて使えばよい。強制放電させる場合は `sudo tlp discharge BAT0` が使えるが完全放電まで走る。

### 回避策

- 長時間シャットダウンする際は AC を抜いておく
- 席を離れる際はシャットダウンではなくサスペンドにする (EC が通電を維持し閾値が保たれる)

同じ性質は t14g4 (65/70) にも当てはまる。

## 計測方法

サスペンド中の消費はサスペンド前後の `energy_now` の差分から求める (サスペンド中は `power_now` を読めないため)。

```console
# AC を抜いた状態で記録
$ cat /sys/class/power_supply/BAT0/energy_now; date +%s
# 蓋を閉じて 30 分以上放置し、復帰後に再度記録して差分を取る
```

S0ix 滞在率は以下で確認する (要 root、s2idle 時のみ意味を持つ)。

```console
sudo cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec
```

サスペンド前後の差分を経過時間で割った値が 90% 以上あれば正常。
