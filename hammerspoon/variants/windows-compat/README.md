# Windows互換モード

Windows のキー操作を macOS 上で再現する Hammerspoon 設定。
一時的に Mac を使用する Windows ユーザーを対象とする。

## キーの対応方針

キーは刻印ではなく物理位置で対応させる。

| 位置 | Windows のキー | Mac のキー | 本設定での役割 |
|---|---|---|---|
| 左下隅 | Ctrl | ⌃ control | Ctrl 系ショートカット |
| スペースの横 | Alt | ⌘ command | Alt+Tab / Alt+F4 |

## 機能

| キー | 動作 | Windows の対応操作 |
|---|---|---|
| ⌃C / ⌃V / ⌃X / ⌃Z / ⌃A / ⌃S / ⌃F 等 | ⌘ に変換 | Ctrl+C 等 |
| ⌃Y | やり直し（⌘⇧Z） | Ctrl+Y |
| Home / End | 行頭 / 行末（⇧ で選択） | Home / End |
| ⌃Home / ⌃End | 文書の先頭 / 末尾 | Ctrl+Home / End |
| ⌃← / ⌃→ | 単語移動（⇧ で選択） | Ctrl+← / → |
| ⌃Backspace | 単語削除 | Ctrl+Backspace |
| ⌘Tab（⇧ で逆順） | ウィンドウ単位の切替 | Alt+Tab |
| ⌘F4 | ウィンドウを閉じる（最後のウィンドウであればアプリを終了） | Alt+F4 |
| ⌃⌥⌘W / メニューバーの Win 表示をクリック | 有効 / 無効の切替 | — |

## 導入と復元

```sh
./hammerspoon/variants/windows-compat/install.sh              # 導入（既存の init.lua を退避）
./hammerspoon/variants/windows-compat/install.sh --uninstall  # 退避した init.lua を復元
```

一時的に無効化する場合は、メニューバーの表示を Mac に切り替える。
本設定は macOS のシステム設定を変更しない。Hammerspoon を終了すると、すべての変換が解除される。

## カスタマイズ

`init.lua` 冒頭の変更箇所を編集する。

- `CTRL_TO_CMD`: ⌘ に変換するキー
- `EXCLUDE_APPS`: 変換の対象外とするアプリの bundle ID

アプリの bundle ID は次のコマンドで確認できる。

```sh
osascript -e 'id of app "iTerm"'
```

## 除外アプリの例

ターミナルでは ⌃C がプロセスの中断に割り当てられている。変換を適用すると ⌘C（コピー）となり中断できなくなるため、
Terminal / iTerm2 / cmux / Ghostty / Warp / kitty / WezTerm / Alacritty を初期設定で除外している。

## 注意事項

- アクセシビリティ権限が必要である（システム設定 → プライバシーとセキュリティ → アクセシビリティ）。
- パスワード入力欄などのセキュア入力中は、macOS の仕様により変換が適用されない。
- Mac 内蔵キーボードの F4 は特殊キーとして動作するため、⌘F4 は fn を併用して入力する。
  または、システム設定で「F1、F2 などのキーを標準のファンクションキーとして使用」を有効にする。
- 除外アプリ以外では、⌃ 系の macOS 標準ショートカット（⌃A / ⌃E による行頭・行末移動等）は使用できない。
- VSCode の統合ターミナルはアプリ単位で判別できないため、変換の対象となる。
- 実機での確認事項: ⌘Tab の上書き、⌃← / ⌃→（macOS のデスクトップ切替と同じキー）の動作。
