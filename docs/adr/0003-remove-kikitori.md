---
status: accepted
date: 2026-10-10
---

# ADR-0003: kikitori（音声入力）を nixfiles から外す

## 背景

音声入力は 2026-08 に自作の kikitori へ一本化した（前身は voxtype）。r995 で `kikitorid` が常駐し、tailscale0 の
41717 番で他ホストに公開していたが、使っていない。`kikitorid` は常駐で約 430MB のメモリを占める。

nixfiles には kikitori のために、flake の input、`pkgs.kikitori` を足す overlay、home-manager モジュールの公開、
`modules/home/parts/voice-input.nix`（COSMIC の Super+V と接続先の切り替え）、r995 のファイアウォールの穴があった。

## 検討した案

- 案 A: エンジンだけ止める（`services.kikitori.enable = false`）。input と overlay とショートカットが残り、
  ショートカットを押してもバーが出ずに待機するだけの壊れた機能になる
- 案 B（採用）: nixfiles から全部外し、再開に要る知識は kikitori のリポジトリに置く

## 決定と理由

案 B にする（ユーザーの判断）。再開時に nixfiles の履歴をたどらなくて済むよう、組み込み手順は kikitori の
`docs/NIXOS.md` に移した。

- **overlay は要らない**: overlay が要ったのは、`enable = false` のクライアントホストが `pkgs.kikitori` 以外に
  パッケージを得る手段を、モジュールが持たなかったため。kikitori 側に `services.kikitori.package` オプションを
  足し（tagawa0525/kikitori#20）、`lib.getExe config.services.kikitori.package` で得られるようにした。再開時に overlay は
  足さない
- **設計判断**: evdev を使わない理由、ペーストキー方式を採らない理由、whisper ではなく SenseVoice を使う理由は
  kikitori の `docs/HANDOFF.md` にある

## 再開するとき

kikitori の `docs/NIXOS.md` の手順に従う。nixfiles 側では次を足す。

- `flake.nix` に input、`home-manager.sharedModules` にモジュール
- r995 で `services.kikitori.enable = true` と `tcp = "0.0.0.0:41717"`、tailscale0 のファイアウォールに 41717
- COSMIC のショートカット（Super+V）。接続先は引数 `--socket r995:41717` で渡す（理由は `docs/NIXOS.md`）

## 確認

- 3 ホストの構成が評価できる（`run-checks.sh` が `ALL_OK`）
