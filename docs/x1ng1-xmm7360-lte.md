# x1ng1: Intel XMM7360 LTE 対応検討メモ

ThinkPad X1 Nano (1st Gen) 内蔵 Intel XMM7360 (PCI `8086:7360`) を NixOS で LTE 接続させようとした際の調査記録。**現状ではフル接続まで到達せず、`hosts/x1ng1/default.nix` からは関連 overlay/設定を一旦撤去している。**

## 何が起きるか (現状: nixpkgs デフォルト ModemManager 1.24.2)

- カーネル 7.0.x の `iosm` ドライバが `/dev/wwan0at{0,1}`, `/dev/wwan0xmmrpc0` を生成する。
- ModemManager 1.24.2 は XMM7360 RPC モード未対応で、`Intel XMM7360 in RPC mode not supported` を返してモデムを認識しない。
- そのため LTE は機能しない (NetworkManager から WWAN を選べない)。

Windows では同じハードウェア + SIM (DMM mobile, DOCOMO 系 MVNO) で正常に通信できることを確認済み。Linux 側ソフトスタックの問題。

## 検証で到達したところ (overlay 一式を入れた状態)

1. **ModemManager を 1.25.95-dev + MR !1421 に差し替え**  
   ✅ XMM7360 RPC モードでモデム認識

2. **libqmi を main HEAD (`11f89ad8`) で scoped override**  
   ✅ `QMI_WDS_PDP_TYPE_NON_IP` 解決、連鎖リビルド回避

3. **FCC unlock スクリプト配置** (`networking.modemmanager.fccUnlockScripts`)  
   ✅ FCC ロック突破

4. **ModemManager systemd path に `xxd` 追加**  
   ✅ スクリプト実行可能に

5. **EPS bearer verify bypass patch 適用**  
   ✅ DMM mobile の attach APN + PAP 認証が成功扱いに

6. **APN 設定コマンド実行**  
   ✅ Successfully set

7. **modem AT 確認**  
   ✅ modem 側にも反映

8. **ModemManager 有効化**  
   ✅ state=enabled, power=on

9. **実通信 (PLMN サーチ → attach → bearer)**  
   ❌ 一切達せず

## ブロッカ (overlay を入れても解決できなかった)

modem の AT 応答からは「物理 RF レイヤで PLMN を一切認識していない」状態:

- `AT+CFUN?` → `+CFUN: 1,0` (full functionality 動作中)
- `AT+XACT?` → `+XACT: 4,2,1,...,103,...,128,...` (LTE only、DOCOMO B1/B3/B19/B28 含む)
- `AT+CSQ` → `+CSQ: 99,99` (測定不能)
- `AT+XCESQ?` → `+XCESQ: 0,99,99,255,255,255,255,255` (RSRP/RSRQ 全て 255 = 受信なし)
- `AT+XREG?` → `+XREG: 0,0,BAND_INVALID,0` (**state 0 = not registered, not searching**)
- `AT+COPS=?` / `AT+COPS=0` → 即時 `No network service`
- `AT+XCEER` → `+XCEER: 248,107` (cause 107: no usable cell)

つまり ModemManager+iosm 範囲は完璧に設定済みでも、modem 側が「自発的に PLMN サーチを開始しない」状況。Windows ドライバは追加の RF init RPC を送って RF を完全に起動していると推測される。

参考: [xmm7360-pci](https://github.com/xmm7360/xmm7360-pci) の `open_xdatachannel.py` には Linux iosm + ModemManager の現状実装にはない一連の RPC 送信があり、これが Windows ドライバとのギャップを埋めている可能性。

## 後日の検討候補

1. **ModemManager 1.26.0 stable を待つ** (nixpkgs に取り込まれれば overlay 不要)。
2. **xmm7360-pci を併用**して RF init を補い、ModemManager は接続管理のみに使う構成を試す。
3. **上流 ModemManager に bug report** (debug ログは `journalctl -u ModemManager.service` から取得済の体裁が分かっている)。
4. **iosm カーネルドライバ側**で XMM7360 のフル RF init をやるパッチが入るのを待つ。

## 一旦撤去した設定 (再現したくなったときのために)

撤去前の `hosts/x1ng1/default.nix` には以下が含まれていた。

```nix
{ lib, pkgs, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev:
      let
        libqmiForMM = prev.libqmi.overrideAttrs (_oldAttrs: {
          version = "1.38.0+main";
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "mobile-broadband";
            repo = "libqmi";
            rev = "11f89ad8";
            hash = "sha256-VNhthRoQ2POY8UVeNEplvoqTM/4feNTp8IQjp8bd7bg=";
          };
        });
      in
      {
        modemmanager = (prev.modemmanager.override { libqmi = libqmiForMM; }).overrideAttrs (oldAttrs: {
          version = "1.25.95-dev+1421";
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "mobile-broadband";
            repo = "ModemManager";
            rev = "87c88dc2";
            hash = "sha256-3Pf5bCfQ3zRop2jfdwgQt2a0kSHMug5NOTKthb+3zxs=";
          };
          patches = (oldAttrs.patches or [ ]) ++ [
            ./patches/modemmanager-skip-eps-bearer-verify.patch
          ];
        });
      })
  ];
  networking.modemmanager = {
    enable = true;
    fccUnlockScripts = [
      {
        id = "8086:7360";
        path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/8086:7360";
      }
    ];
  };
  systemd.services.ModemManager.path = [ pkgs.xxd ];
}
```

そして `hosts/x1ng1/patches/modemmanager-skip-eps-bearer-verify.patch` の中身:

```diff
--- a/src/mm-iface-modem-3gpp.c
+++ b/src/mm-iface-modem-3gpp.c
@@ -1266,11 +1266,12 @@ handle_set_initial_eps_bearer_settings_reload_ready (MMIfaceModem3gpp
     if (ctx->saved_error)
         mm_obj_warn (self, "failed reloading initial EPS bearer settings after update: %s", ctx->saved_error->message);
     else if (!mm_bearer_properties_cmp (new_config, ctx->config, MM_BEARER_PROPERTIES_CMP_FLAGS_EPS)) {
-        mm_obj_warn (self, "requested and reloaded initial EPS bearer settings don't match");
+        mm_obj_warn (self, "requested and reloaded initial EPS bearer settings don't match (treating as success: plugin lacks load_initial_eps_bearer_settings)");
         mm_obj_info (self, "reloaded initial EPS bearer settings:");
         mm_log_bearer_properties (self, MM_LOG_LEVEL_INFO, "  ", new_config);
-        ctx->saved_error = g_error_new_literal (MM_CORE_ERROR, MM_CORE_ERROR_FAILED,
-                                                "Initial EPS bearer settings were not updated");
+        /* set succeeded on the modem; publish the requested config on D-Bus */
+        dictionary = mm_bearer_properties_get_dictionary (ctx->config);
+        mm_gdbus_modem3gpp_set_initial_eps_bearer_settings (ctx->skeleton, dictionary);
     } else {
         dictionary = mm_bearer_properties_get_dictionary (new_config);
         mm_gdbus_modem3gpp_set_initial_eps_bearer_settings (ctx->skeleton, dictionary);
```

ビルドの注意: ModemManager+libqmi の overlay を入れると 1 回目だけ ModemManager のフルビルドが r995 で発生する (DEBUG flag を入れて検証を回した時は依存連鎖で electron-unwrapped 等が巻き込まれ、5 時間級になった)。再現する際はビルド時間を覚悟する。
