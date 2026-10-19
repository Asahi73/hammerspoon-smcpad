-- =====================================================================
-- Windows互換モード (Hammerspoon)
-- =====================================================================
-- Windows のキー操作を macOS 上で再現する。
-- キーの対応は刻印ではなく物理位置に基づく。
--   左下隅の ⌃ (Windows の Ctrl の位置) → Ctrl 系ショートカット
--   スペース横の ⌘ (Windows の Alt の位置) → Alt+Tab / Alt+F4
--
-- 機能:
--   1. ⌃C/V/X/Z/Y/A/S/F 等を ⌘ に変換する（除外アプリでは変換しない）
--   2. Home/End → 行頭/行末、⌃←/→ → 単語移動、⌃Backspace → 単語削除
--   3. ⌘Tab → ウィンドウ単位の切替、⌘F4 → ウィンドウを閉じる
--   4. メニューバーの Win 表示のクリック、または ⌃⌥⌘W で有効/無効を切り替える
--
-- 設定変更後は Hammerspoon コンソールで hs.reload() を実行する。
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- 変換の対象外とするアプリの bundle ID。
-- ⌃ 付きのキーに固有の機能を割り当てているアプリを登録する。
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

-- ⌃+キー を ⌘+キー に変換する対象。値で変換後のキーと ⇧ の付加を指定できる。
-- ⌃⇧+キー は ⌘⇧+キー に変換する。
local CTRL_TO_CMD = {
  a = {}, c = {}, v = {}, x = {}, z = {},
  s = {}, f = {}, n = {}, o = {}, p = {},
  w = {}, t = {}, r = {}, l = {},
  b = {}, i = {}, u = {},
  y = { key = "z", shift = true },  -- やり直し: Ctrl+Y → ⌘⇧Z
}

-- 有効/無効を切り替えるホットキー
local TOGGLE_MODS, TOGGLE_KEY = { "ctrl", "alt", "cmd" }, "w"

-- 読み込み時に有効にするか
local ENABLED_ON_START = true

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

local K = hs.keycodes.map

-- ローカル変数からのみ参照されるオブジェクトは GC で回収され、
-- eventtap やホットキーが停止する。グローバルな表に保持して回収を防ぐ。
WinCompat = WinCompat or {}
local M = WinCompat

-- ---------------------------------------------------------------------
-- 最前面アプリの記録
-- ---------------------------------------------------------------------
-- キー入力ごとに最前面アプリを問い合わせる処理を避けるため、
-- アプリ切替時に bundle ID を記録し、キー変換ではその値を参照する。
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
-- 受け取ったイベントのキーコードと修飾キーを書き換えて通過させる。
-- 新しいイベントを送出しないため、変換後のイベントが再びこの処理に入ることはない。

-- keycode → 変換ルール
local ctrlRules = {}
for key, rule in pairs(CTRL_TO_CMD) do
  ctrlRules[K[key]] = { code = K[rule.key or key], shift = rule.shift }
end

-- 修飾キーを置き換える。矢印キー等に付く fn フラグは維持する。
local function rewrite(e, code, flags, orig)
  flags.fn = orig.fn
  e:setKeyCode(code)
  e:setFlags(flags)
  return false  -- false: 書き換えたイベントを通過させる
end

local function onKey(e)
  if EXCLUDE_APPS[M.frontBundleID] then return false end

  local code = e:getKeyCode()
  local f = e:getFlags()
  local shift = f.shift or nil

  -- ⌃ のみ（⇧ の併用は可）
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

  -- 修飾キーなし（⇧ の併用は可）の Home/End → 行頭/行末
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

-- keyDown と keyUp に同じ規則を適用し、押下と離上の対応を揃える。
M.keyTap = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, onKey)

-- macOS は応答が遅延した eventtap を無効化する。一定間隔で状態を確認し、再開する。
M.tapWatchdog = hs.timer.new(5, function()
  if M.enabled and not M.keyTap:isEnabled() then
    print("[wincompat] eventtap を再開")
    M.keyTap:start()
  end
end)

-- ---------------------------------------------------------------------
-- 3. Alt+Tab / Alt+F4（物理位置に合わせて ⌘Tab / ⌘F4 に割り当てる）
-- ---------------------------------------------------------------------
-- hs.window.switcher は修飾キーを離した時点で選択中のウィンドウに切り替える。
M.switcher = hs.window.switcher.new()
M.switcher.ui.showThumbnails = false
M.switcher.ui.showSelectedThumbnail = false

-- Alt+F4 相当: ウィンドウを閉じる。アプリの最後のウィンドウであればアプリを終了する。
local function closeLikeWindows()
  local win = hs.window.focusedWindow()
  if not win then return end
  local app = win:application()

  local count = 0
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then count = count + 1 end
  end

  -- Finder は終了の対象外とする（デスクトップ表示を担うため）
  if count <= 1 and app:bundleID() ~= "com.apple.finder" then
    app:kill()   -- 通常の終了（⌘Q 相当）。強制終了は kill9()
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
-- 4. 有効 / 無効の切替
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
    M.menubar:setTooltip(on and "Windows互換: 有効（クリックで無効化）"
                              or "Windows互換: 無効（クリックで有効化）")
  end
  hs.alert.show(on and "Windows互換: 有効" or "Windows互換: 無効")
end

local function toggle() setEnabled(not M.enabled) end

if M.menubar then M.menubar:setClickCallback(toggle) end
M.toggleHotkey = hs.hotkey.bind(TOGGLE_MODS, TOGGLE_KEY, toggle)

setEnabled(ENABLED_ON_START)
