---
status: accepted
date: 2026-10-10
---

# ADR-0002: NetBox を r995 から外す

## 背景

r995 で NetBox（DCIM/IPAM）を常時動かしていたが、使っていない。常駐で NetBox の `manage.py` 2 本と gunicorn が
合計約 1.25GB のメモリを占め、PostgreSQL・Redis・nginx も付随して動いている。

## 検討した案

- 案 A: 動かしたまま放置する。メモリと保守（NetBox のバージョンが EOL になるたびの更新）の費用だけが残る
- 案 B: `systemctl stop` で止めるだけにする。再起動や `nixos-rebuild` で元に戻る
- 案 C（採用）: 設定から外す

## 決定と理由

案 C にする（ユーザーの判断）。使っていないものを設定に残すと、更新のたびに評価・ビルドの対象になり、NetBox の
バージョン固定（下記）のような保守も続く。

- **残るもの**: データは消さない。`/var/lib/netbox`（SECRET_KEY・API トークン pepper・メディア）と、
  PostgreSQL の `netbox` データベースとロール、Redis の状態がホストに残る。消すかどうかは別に判断する
- **PostgreSQL**: 15432 番への退避は atuin 用なので残す

## 再開するとき

外した設定は次のとおり。NetBox を再び動かすなら、`hosts/r995/default.nix` に戻す。

```nix
services.netbox = {
  enable = true;
  # stateVersion 26.05 の既定は netbox_4_5 だが、4.5 系は EOL で insecure 指定、
  # 4.6 系は nixpkgs から削除された。外した時点では 4.7 を明示していた
  package = pkgs.netbox_4_7;
  # DATABASES を定義すると既定値ごと置き換わるため全項目を書く。
  # UNIX ソケットのファイル名がポート番号を含む（.s.PGSQL.15432）ので PORT が要る
  settings.DATABASES.default = {
    NAME = "netbox";
    USER = "netbox"; # UNIX ソケットの peer 認証
    HOST = "/run/postgresql";
    PORT = "15432";
  };
  nginx = {
    enable = true;
    hostname = "r995";
  };
};
# NetBox 4.7 で housekeeping コマンドが廃止され、netbox-rq 上の日次ジョブが代行する。
# 上流モジュールは netbox-housekeeping.service だけ削除してタイマーを残したため、
# 起動のたびに「unit to trigger not loaded」で失敗する。上流でタイマーが消えたら不要
systemd.timers.netbox-housekeeping.enable = false;
# Tailscale の MagicDNS FQDN（r995.<tailnet>.ts.net）で来たリクエストも落とすため
services.nginx.virtualHosts."r995".default = true;
# tailscale0 の allowedTCPPorts に 80 を足す
```

初回のみ管理ユーザーの作成が要る: `sudo netbox-manage createsuperuser`。

## 確認

- r995 の構成が評価できる（`nix eval .#nixosConfigurations.r995.config.system.build.toplevel.drvPath`）

## 補足

- 2026-10-11: ユーザーの判断でデータを消した（`/var/lib/netbox`、`/var/lib/redis-netbox`、PostgreSQL の `netbox`
  データベースとロール）。再開するときは空のデータから始まる
