---
status: accepted
date: 2026-10-28
requires: []
supersedes: []
superseded-by:
issues: []
---

# ADR-0063: VS Code Server の node は patchelf で書き換えず nixpkgs の node で起動する

## 背景

VS Code 1.143.1（サーバー同梱の node 24.22.1）で r995 への Remote-SSH が「Connection closed」になった。
クライアントのログでは、サーバーの展開後の整合性チェック `code-server --version` が node の segfault（終了コード 139）で
失敗し、VS Code が staging を捨てて再ダウンロードを繰り返していた。

nixos-vscode-server は同梱の node を `patchelf --set-interpreter ... --set-rpath ...` で書き換える。
同じ node（2026-10-28 に r995 と x1ng1 で確認）で次を測った。

| 操作                                                     | 結果     |
| -------------------------------------------------------- | -------- |
| パッチなし（nix-ld 経由）                                | 起動する |
| patchelf 0.19.2 で interpreter と rpath を同時指定       | segfault |
| patchelf 0.19.2 で interpreter の後に rpath              | segfault |
| patchelf 0.19.2 で rpath の後に interpreter              | 起動する |
| patchelf 0.19.2 で interpreter だけ、または rpath だけ   | 起動する |
| patchelf 0.18.0（nixpkgs の patchelfUnstable）で同時指定 | segfault |
| patchelf 0.15.2 で同時指定                               | 起動する |

つまり新しい patchelf が、この node（デバッグ情報つきの大きな ELF）の書き換えで壊す。上流モジュールは同時指定してから
`--shrink-rpath` を実行するので、必ず当たる。

## 検討した案

- **nodejsPackage に pkgs.nodejs_24 を指定する（採用）**: モジュールの公式オプション。ラッパーが nixpkgs の node を
  exec するので、同梱の node は書き換えた結果を使わない
- patchelf を 0.15.2 に固定する: overlay が要り、古い版を保守し続ける。ほかの ELF にも新しい patchelf の不具合が
  ある可能性は残る
- enableFHS を有効にする: node を FHS 環境で包むので起動が重く、拡張機能が見る環境も変わる
- パッチを止めて nix-ld に任せる: 上流モジュールにパッチを止めるオプションが無い。サービスを消すと、nix-ld の無い
  ホストで動かなくなる
- 上流の修正を待つ: 修正の時期が分からず、その間 r995 に接続できない

## 決定と理由

`services.vscode-server.nodejsPackage = pkgs.nodejs_24` を指定する。公式オプションだけで直り、上流の修正後も
外せば元に戻る。nixpkgs の node は 24.21.0 で同梱の 24.22.1 と ABI（メジャー版）が同じなので、同梱のネイティブモジュールが動く。

### 帰結

- 同梱の node は書き換えた結果が壊れたまま残るが、使われない
- VS Code が要求する node のメジャー版が上がったら、`nodejs_NN` を合わせる

### 確認

r995 に反映後、Remote-SSH で `~/github/xlc` を開けること。
