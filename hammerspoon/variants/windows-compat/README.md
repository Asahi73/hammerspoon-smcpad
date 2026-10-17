# Windows互換モード

Windowsユーザーが一時的にMacを使うときに、手癖のまま操作できるようにする Hammerspoon 設定。
OSの設定は変更しないので、Hammerspoon を止めれば素のMacに戻る。

## キーの考え方: 刻印ではなく「位置」で合わせる

Windowsの手癖はキーの位置で覚えている。

| Windowsでの位置 | Windowsのキー | Macで同じ位置のキー | このモードでの扱い |
|---|---|---|---|
| 左下隅 | Ctrl | ⌃ control | Ctrl系ショートカット |
| スペースの横 | Alt | ⌘ command | Alt+Tab / Alt+F4 |

## できること

| 押すキー | 動作 | Windowsでいう |
|---|---|---|
| ⌃C / ⌃V / ⌃X / ⌃Z / ⌃A / ⌃S / ⌃F など | ⌘ に変換 | Ctrl+C など |
| ⌃Y | やり直し（⌘⇧Z） | Ctrl+Y |
| Home / End | 行頭 / 行末（⇧で選択） | Home / End |
| ⌃Home / ⌃End | 文書の先頭 / 末尾 | Ctrl+Home / End |
| ⌃← / ⌃→ | 単語移動（⇧で選択） | Ctrl+← / → |
| ⌃Backspace | 単語削除 | Ctrl+Backspace |
| ⌘Tab（⇧で逆順） | **ウィンドウ単位**で切替 | Alt+Tab |
| ⌘F4 | ウィンドウを閉じる（最後の1枚ならアプリ終了） | Alt+F4 |
| メニューバーの「Win」をクリック / ⌃⌥⌘W | ON/OFF 切替 | — |

変換対象・除外アプリは `init.lua` 冒頭の `CTRL_TO_CMD` と `EXCLUDE_APPS` で変えられる。
ターミナル系（Terminal / iTerm2 / cmux / Ghostty など）では変換しないので、⌃C で中断できる。

## 導入と戻し方

```sh
./hammerspoon/variants/windows-compat/install.sh              # 導入（既存の init.lua は退避）
./hammerspoon/variants/windows-compat/install.sh --uninstall  # 元の init.lua に戻す
```

一時的に止めたいだけなら、メニューバーの「Win」をクリックして「Mac」にする。

## 注意

- **アクセシビリティ権限**が必要（システム設定 → プライバシーとセキュリティ → アクセシビリティ）。
- パスワード入力欄などの「セキュア入力」中は、macOS の仕様で変換が効かない。
- Macの内蔵キーボードでは F4 が特殊キーになっているので、⌘F4 は fn を足して ⌘fnF4 と押す
  （または「F1、F2などのキーを標準のファンクションキーとして使用」をオンにする）。
- ⌃ 系の Mac 標準ショートカット（⌃A / ⌃E での行頭・行末移動など）は、ターミナル以外では使えなくなる。
- VSCode の統合ターミナルはアプリ単位で判別できないため変換対象になる。
- 要実機確認: ⌘Tab の上書き、⌃←/→（macOSのデスクトップ切替と同じキー）が意図どおりに効くか。
