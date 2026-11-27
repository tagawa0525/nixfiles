# =============================================================================
# r995 の ncsoft 共有（Samba）
# =============================================================================
# NC の解析資料（ゲームのコピー、メモリのダンプ、Ghidra のプロジェクト。数十〜数百 GB）を r995 のローカルの
# btrfs に置き、r995 の Ghidra（./ghidra.nix）はここをローカルで読み書きし、Windows の PC は SMB で同じ場所を
# 読み書きする。NFS（modules/slurm/server.nix）は Windows から使えないので、Windows 向けにだけ Samba を足す。
#
# 決定と、検討した代わりの案は docs/adr/0084-serve-ncsoft-share-over-samba-on-tailscale.md。
# 受け付けるのは Tailscale（tailscale0、100.64.0.0/10）だけ。Samba のパスワードは秘密なので nix に書かない。
# 初回に、利用者が r995 で `sudo smbpasswd -a tagawa` を実行して決める。
{ ... }:

let
  share = "/srv/ncsoft";
in
{
  # /srv は btrfs の root と同じ容量（/home と共有）。ハードリンクはこの中で使える
  systemd.tmpfiles.rules = [ "d ${share} 0750 tagawa users -" ];

  services.samba = {
    enable = true;
    # ファイアウォールは tailscale0 にだけ開ける（下）。openFirewall は全インターフェイスに開けるので使わない
    openFirewall = false;
    # 名前解決（nmbd）とドメイン（winbindd）は使わず、IP かホスト名で \\<host>\ncsoft を開く
    nmbd.enable = false;
    winbindd.enable = false;
    settings = {
      global = {
        security = "user";
        "server min protocol" = "SMB2";
        "map to guest" = "never";
        "restrict anonymous" = 2;
        # ファイアウォールに加え、Tailscale 以外の送信元は Samba の側でも断る。IPv6 の送信元も断るよう、
        # deny は ALL にし、allow に Tailscale の IPv6（fd7a:115c:a1e0::/48）と loopback を並べる
        "hosts allow" = "100.64.0.0/10 127.0.0.1 fd7a:115c:a1e0::/48 ::1";
        "hosts deny" = "ALL";
        # r995 の Ghidra が同じファイルをローカルで書き換える。SMB のクライアントの oplock と lease は
        # ローカルの書き込みでは破られず、Windows が古いキャッシュを返すので、使わない
        "smb2 leases" = "no";
        "smb ports" = 445;
        # 共有を出すだけで、プリンタは使わない
        "load printers" = "no";
        printing = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
      };
      ncsoft = {
        path = share;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "tagawa";
        # 共有の中を指すリンクは、smbd がサーバー側で辿って Windows に実体として見せる（follow symlinks の既定は yes）。
        # 共有の外を指すリンクは辿らない（wide links の既定は no）。どちらも既定のままだが、挙動の前提なので明示する
        "follow symlinks" = "yes";
        "wide links" = "no";
        # r995 の Ghidra（tagawa）と同じ所有者で作る
        "force user" = "tagawa";
        "force group" = "users";
        oplocks = "no";
        "level2 oplocks" = "no";
        # Windows から作ったファイルには実行ビットを付けない（データの置き場。実行は r995 で chmod する）
        "create mask" = "0640";
        "directory mask" = "0750";
      };
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    445 # SMB（ncsoft 共有）
  ];
}
