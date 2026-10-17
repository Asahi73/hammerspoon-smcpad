-- =====================================================================
-- Windows互換モード (Hammerspoon)
-- =====================================================================
-- Windowsユーザーが一時的にMacを使うときに、手癖のまま操作できるようにする。
-- キーは「刻印」ではなく「位置」で合わせる:
--   左下隅の ⌃ (Windowsの Ctrl の位置) → Ctrl系ショートカット
--   スペース横の ⌘ (Windowsの Alt の位置) → Alt+Tab / Alt+F4
--
-- 主な機能:
--   1. ⌃C/V/X/Z/Y/A/S/F… を ⌘ に変換（ターミナル系アプリは変換しない）
--   2. Home/End → 行頭/行末、⌃←/→ → 単語移動、⌃Backspace → 単語削除
--   3. ⌘Tab（Alt+Tabの位置）→ ウィンドウ単位の切替、⌘F4 → ウィンドウを閉じる
--   4. メニューバーの「Win」をクリック or ⌃⌥⌘W で ON/OFF
--
-- OSの設定は一切変更しない。Hammerspoonを終了すれば素のMacに戻る。
-- 再読み込み: Hammerspoonコンソールで hs.reload()
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- 変換しないアプリ（bundle ID）。ターミナルでは ⌃C = 中断 などをそのまま使うため。
-- bundle ID の調べ方: osascript -e 'id of app "iTerm"'
local EXCLUDE_APPS = {
  ["com.apple.Terminal"]          = true,
  ["com.googlecode.iterm2"]       = true,
  ["com.cmuxterm.app"]            = true,
  ["com.mitchellh.ghostty"]       = true,
  ["dev.warp.Warp-Stable"]        = true,
  ["net.kovidgoyal.kitty"]        = true,
  ["com.github.wez.wezterm"]      = true,
  ["org.alacritty"]               = true,
}

-- ⌃+キー → ⌘+キー に変換するキー。値は変換後のキー（shift = true で ⇧ を足す）。
-- ⌃⇧+キーは ⌘⇧+キー になる（例: ⌃⇧T → ⌘⇧T でタブを開き直す）。
local CTRL_TO_CMD = {
  a = {}, c = {}, v = {}, x = {}, z = {},
  s = {}, f = {}, n = {}, o = {}, p = {},
  w = {}, t = {}, r = {}, l = {},
  b = {}, i = {}, u = {},
  y = { key = "z", shift = true },  -- やり直し: Windows Ctrl+Y → Mac ⌘⇧Z
}

-- ON/OFF 切替のホットキー
local TOGGLE_MODS, TOGGLE_KEY = { "ctrl", "alt", "cmd" }, "w"

-- 起動時に有効にするか
local ENABLED_ON_START = true

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

local K = hs.keycodes.map

-- Hammerspoon はローカル変数しか参照していないオブジェクトをGCで回収することがある。
-- eventtap やホットキーが突然効かなくなるのを防ぐため、グローバルな表に保持する。
WinCompat = WinCompat or {}
local M = WinCompat

-- ---------------------------------------------------------------------
-- 最前面アプリ（毎キー問い合わせると重いので、切替時にだけ更新する）
-- ---------------------------------------------------------------------
local function currentBundleID()
  local app = hs.application.frontmostApplication()
  return app and app:bundleID()
end

M.frontBundleID = currentBundleID()
M.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated then
    M.frontBundleID = app and app:bundleID()
  end
end)

-- ---------------------------------------------------------------------
-- 1 & 2. キー変換（eventtap）
-- ---------------------------------------------------------------------
-- 新しいイベントを送り直すのではなく、届いたイベントのキーと修飾キーを書き換えて流す。
-- こうすると変換後のキーが再びこの関数に入ってくる（無限ループ）心配がない。

-- keycode → 変換ルール
local ctrlRules = {}
for key, rule in pairs(CTRL_TO_CMD) do
  ctrlRules[K[key]] = { code = K[rule.key or key], shift = rule.shift }
end

-- 修飾キーを置き換える。矢印キー等は fn フラグ付きで届くので、それは残す。
local function rewrite(e, code, flags, orig)
  flags.fn = orig.fn
  e:setKeyCode(code)
  e:setFlags(flags)
  return false  -- false = 書き換えたイベントをそのまま流す
end

local function onKey(e)
  if EXCLUDE_APPS[M.frontBundleID] then return false end

  local code = e:getKeyCode()
  local f = e:getFlags()
  local shift = f.shift or nil

  -- ⌃ 単独（⇧ は可）
  if f.ctrl and not f.cmd and not f.alt then
    local rule = ctrlRules[code]
    if rule then
      return rewrite(e, rule.code, { cmd = true, shift = shift or rule.shift }, f)
    end
    if code == K.left or code == K.right then           -- 単語移動
      return rewrite(e, code, { alt = true, shift = shift }, f)
    end
    if code == K.delete then                             -- 単語削除（Backspace）
      return rewrite(e, code, { alt = true }, f)
    end
    if code == K.home then                               -- 文書の先頭
      return rewrite(e, K.up, { cmd = true, shift = shift }, f)
    end
    if code == K["end"] then                             -- 文書の末尾
      return rewrite(e, K.down, { cmd = true, shift = shift }, f)
    end
    return false
  end

  -- 修飾なし（⇧ は可）の Home/End → 行頭/行末
  if not f.ctrl and not f.cmd and not f.alt then
    if code == K.home then
      return rewrite(e, K.left, { cmd = true, shift = shift }, f)
    end
    if code == K["end"] then
      return rewrite(e, K.right, { cmd = true, shift = shift }, f)
    end
  end

  return false
end

-- keyUp も同じ規則で書き換え、押下と離上の組み合わせを揃える。
M.keyTap = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, onKey)

-- macOS は処理が遅れた eventtap を黙って無効化することがある。定期的に確認して戻す。
M.tapWatchdog = hs.timer.new(5, function()
  if M.enabled and not M.keyTap:isEnabled() then
    print("[wincompat] eventtap が止まっていたので再開")
    M.keyTap:start()
  end
end)

-- ---------------------------------------------------------------------
-- 3. Alt+Tab / Alt+F4（位置ベースなので ⌘Tab / ⌘F4）
-- ---------------------------------------------------------------------
-- hs.window.switcher は修飾キーを離した時点で選択中のウィンドウへ切り替える。
M.switcher = hs.window.switcher.new()
M.switcher.ui.showThumbnails = false
M.switcher.ui.showSelectedThumbnail = false

-- Windows の Alt+F4: ウィンドウを閉じる。そのアプリの最後のウィンドウならアプリを終了する。
local function closeLikeWindows()
  local win = hs.window.focusedWindow()
  if not win then return end
  local app = win:application()

  local count = 0
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then count = count + 1 end
  end

  -- Finder は終了させない（デスクトップが消えたように見えるため）
  if count <= 1 and app:bundleID() ~= "com.apple.finder" then
    app:kill()   -- kill() は通常の終了（⌘Q 相当）。強制終了は kill9()
  else
    win:close()
  end
end

local function nextWin() M.switcher:next() end
local function prevWin() M.switcher:previous() end

M.hotkeys = {
  hs.hotkey.new({ "cmd" },          "tab", nextWin, nil, nextWin),
  hs.hotkey.new({ "cmd", "shift" }, "tab", prevWin, nil, prevWin),
  hs.hotkey.new({ "cmd" },          "f4",  closeLikeWindows),
}

-- ---------------------------------------------------------------------
-- 4. ON / OFF
-- ---------------------------------------------------------------------
M.menubar = M.menubar or hs.menubar.new()

local function setEnabled(on)
  M.enabled = on
  if on then
    M.keyTap:start()
    M.tapWatchdog:start()
    M.appWatcher:start()
    M.frontBundleID = currentBundleID()
    for _, hk in ipairs(M.hotkeys) do hk:enable() end
  else
    M.keyTap:stop()
    M.tapWatchdog:stop()
    M.appWatcher:stop()
    for _, hk in ipairs(M.hotkeys) do hk:disable() end
  end

  if M.menubar then
    M.menubar:setTitle(on and "Win" or "Mac")
    M.menubar:setTooltip(on and "Windows互換: ON（クリックでOFF）"
                              or "Windows互換: OFF（クリックでON）")
  end
  hs.alert.show(on and "Windows互換 ON" or "Windows互換 OFF（素のMac）")
end

local function toggle() setEnabled(not M.enabled) end

if M.menubar then M.menubar:setClickCallback(toggle) end
M.toggleHotkey = hs.hotkey.bind(TOGGLE_MODS, TOGGLE_KEY, toggle)

setEnabled(ENABLED_ON_START)
