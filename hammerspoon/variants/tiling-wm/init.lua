-- =====================================================================
-- タイル型ウィンドウマネージャ (Hammerspoon)
-- =====================================================================
-- 特定の WM を模倣せず、タイリングとアプリフォーカスを Hammerspoon で扱いやすい形で実装する。
-- 「同じキーをもう一度押すと次へ進む」動きを全体で統一している。
--
-- キー（⌥ = ウィンドウとアプリ、⌃⌥ = スナップ）:
--   ⌥+英字          アプリを起動 / 前面化。前面なら同アプリの次のウィンドウへ
--   ⌥+数字          アプリのまとまりを表示して整列（他のアプリは隠す）。続けて押すと群内でフォーカス巡回
--   ⌥+h/j/k/l       左/下/上/右のウィンドウへフォーカス
--   ⌥+⇧+h/j/k/l     その方向のウィンドウと位置を交換
--   ⌥+Enter         整列。続けて押すとレイアウト切替（メイン+スタック → 横等分 → 全最大化）
--   ⌥+⇧+Enter       フォーカス中のウィンドウをメインにする
--   ⌥+[ / ⌥+]       メイン領域を狭く / 広く
--   ⌥+⇧+Space       フロート切替（整列の対象から外す / 戻す）
--   ⌃⌥+←/→/↑/↓      左/右/上/下に配置。続けて押すと幅が 1/2 → 2/3 → 1/3
--   ⌃⌥+Enter        最大化
--   ⌃⌥+c            中央に配置
--   ⌃⌥+g            グリッドで手動配置
--   ⌃⌥+t            自動整列の ON / OFF（ウィンドウの増減で整列し直す）
--   ⌃⌥+r            設定の再読み込み
--
-- 設定変更後は Hammerspoon コンソールで hs.reload() を実行する（または ⌃⌥+r）。
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- 修飾キー
local MOD       = { "alt" }
local MOD_SHIFT = { "alt", "shift" }
local SNAP_MOD  = { "ctrl", "alt" }

-- ウィンドウ間と画面端の隙間（px）
local GAP = 8

-- メイン領域の初期の幅（画面に対する割合）と、⌥+[ / ] での変化量
local MAIN_RATIO = 0.6
local RATIO_STEP = 0.05

-- アプリ定義。bundleIDs を上から順に試し、見つからなければ name（アプリ名）で探す。
-- bundle ID の調べ方: osascript -e 'id of app "Slack"'
local APPS = {
  chrome     = { name = "Google Chrome",      bundleIDs = { "com.google.Chrome" } },
  vscode     = { name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  pycharm    = { name = "PyCharm",            bundleIDs = { "com.jetbrains.pycharm",         -- Professional
                                                            "com.jetbrains.pycharm.ce" } },  -- Community
  cmux       = { name = "cmux",               bundleIDs = { "com.cmuxterm.app" } },
  claude     = { name = "Claude",             bundleIDs = { "com.anthropic.claudefordesktop" } },
  codex      = { name = "Codex",              bundleIDs = { "com.openai.codex" } },  -- 実機で要確認
  slack      = { name = "Slack",              bundleIDs = { "com.tinyspeck.slackmacgap" } },
  sourcetree = { name = "Sourcetree",         bundleIDs = { "com.torusknot.SourceTreeNotMAS" } },
}

-- ⌥+英字 → アプリ
local APP_KEYS = {
  c = "chrome",
  v = "vscode",
  p = "pycharm",
  t = "cmux",
  a = "claude",
  x = "codex",
  s = "slack",
  g = "sourcetree",
}

-- ⌥+数字 → アプリのまとまり。先頭のアプリがメイン（左側の大きい領域）になる。
local GROUPS = {
  [1] = { "vscode", "cmux" },
  [2] = { "pycharm", "cmux" },
  [3] = { "chrome", "claude" },
}

-- 整列の対象にしないアプリ（bundle ID）。設定画面やダイアログ中心のアプリを登録する。
local EXCLUDE_APPS = {
  ["com.apple.systempreferences"] = true,
  ["com.apple.SystemSettings"]    = true,
  ["com.apple.ActivityMonitor"]   = true,
  ["org.hammerspoon.Hammerspoon"] = true,
}

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

-- ローカル変数からのみ参照されるオブジェクトは GC で回収され、
-- ホットキーやウォッチャーが停止する。グローバルな表に保持して回収を防ぐ。
TilingWM = TilingWM or {}
local M = TilingWM

M.layouts  = { "tall", "columns", "monocle" }
M.layout   = M.layout or 1          -- M.layouts の添字
M.ratio    = M.ratio or MAIN_RATIO
M.order    = M.order or {}          -- 整列順（ウィンドウIDの配列）。先頭がメイン
M.floating = M.floating or {}       -- フロート中のウィンドウID → true
M.lastTile = nil                    -- 直前の整列結果（連打判定用）
M.activeGroup = nil                 -- 直前に表示したまとまりの番号

hs.window.animationDuration = 0

local function log(fmt, ...)
  print(string.format("[tiling] " .. fmt, ...))
end

-- ---------------------------------------------------------------------
-- アプリの解決 / 起動（hammerspoon/init.lua からコピー）
-- ---------------------------------------------------------------------

-- 起動中のアプリを取得する（bundle ID 優先、無ければアプリ名）。未起動なら nil。
local function runningApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    local app = hs.application.get(id)
    if app then return app end
  end
  return hs.application.get(spec.name)
end

-- アプリを起動する（bundle ID を順に試し、最後にアプリ名でフォールバック）。
local function launchApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    if hs.application.launchOrFocusByBundleID(id) then return true end
  end
  if hs.application.launchOrFocus(spec.name) then return true end
  log("起動できない: %s（このMacに未インストール？）", spec.name)
  return false
end

-- ---------------------------------------------------------------------
-- ウィンドウ列挙（別デスクトップ対応、hammerspoon/init.lua からコピー）
-- ---------------------------------------------------------------------
-- macOS は今いるデスクトップのウィンドウしか列挙できない。hs.window.filter は一度認識した
-- ウィンドウをキャッシュし続けるので、別デスクトップのウィンドウも返せる。これを一次ソースにする。
hs.window.filter.forceRefreshOnSpaceChange = true

local WINDOW_FILTER = { allowRoles = "AXStandardWindow" }

-- 保温役: 空フィルタを常時アクティブにして、ウィンドウの追跡を止めない。
M.windowWarmer = hs.window.filter.new(false, "tiling.warm")
M.windowWarmer:keepActive()

M.appFilters = M.appFilters or {}

local function filterForApp(app)
  local name = app:name()
  if not name then return nil end
  if not M.appFilters[name] then
    local wf = hs.window.filter.new(false, "tiling.wf." .. name)
    wf:setAppFilter(name, WINDOW_FILTER)
    wf:keepActive()
    M.appFilters[name] = wf
  end
  return M.appFilters[name]
end

-- 対象アプリの通常ウィンドウを、ウィンドウID順（押すたびに変わらない並び）で返す。
local function standardWindows(app)
  local seen, wins = {}, {}
  local function add(w)
    local id = w and w:id()
    if id and not seen[id] then
      seen[id] = true
      wins[#wins + 1] = w
    end
  end

  local wf = filterForApp(app)
  if wf then
    for _, w in ipairs(wf:getWindows()) do add(w) end   -- 別デスクトップ含む
  end
  for _, w in ipairs(app:allWindows()) do               -- 現デスクトップ分の補完
    if w:isStandard() then add(w) end
  end

  table.sort(wins, function(a, b) return a:id() < b:id() end)
  return wins
end

-- ---------------------------------------------------------------------
-- フォーカス / 巡回（hammerspoon/init.lua からコピー）
-- ---------------------------------------------------------------------

local SPACE_SWITCH_TIMEOUT = 1.5

-- ウィンドウをフォーカスする。別デスクトップにある場合は、そのスペースへ移動してからフォーカスする。
local function focusWindow(win)
  if win:isMinimized() then win:unminimize() end

  local spaces = hs.spaces.windowSpaces(win) or {}
  local screen = win:screen()
  local activeSpace = screen and hs.spaces.activeSpaceOnScreen(screen)

  local onActiveSpace = false
  for _, s in ipairs(spaces) do
    if s == activeSpace then onActiveSpace = true break end
  end

  if onActiveSpace or not spaces[1] or not activeSpace then
    win:focus()
    return
  end

  local target = spaces[1]
  hs.spaces.gotoSpace(target)
  local deadline = hs.timer.secondsSinceEpoch() + SPACE_SWITCH_TIMEOUT
  hs.timer.waitUntil(
    function()
      return hs.spaces.activeSpaceOnScreen(screen) == target
        or hs.timer.secondsSinceEpoch() > deadline
    end,
    function()
      win:raise()
      win:focus()
    end,
    0.05)
end

-- wins の中で、今フォーカスしているウィンドウの次へ移動する（末尾の次は先頭）。
local function focusNextIn(wins)
  if #wins == 0 then return false end
  local current = hs.window.focusedWindow()
  local idx = 0
  if current then
    for i, w in ipairs(wins) do
      if w:id() == current:id() then idx = i break end
    end
  end
  local nextIdx = idx % #wins + 1
  focusWindow(wins[nextIdx])
  return true
end

-- アプリキーの挙動:
--   未起動           → 起動する
--   起動中・非最前面 → そのアプリへフォーカス（直前に使っていたウィンドウ）
--   起動中・最前面   → 同じアプリの次のウィンドウへ巡回
local function focusApp(spec)
  local app = runningApp(spec)
  if not app then
    launchApp(spec)
    return
  end

  local front = hs.application.frontmostApplication()
  if front and front:pid() == app:pid() then
    if focusNextIn(standardWindows(app)) then return end
  else
    local win = app:mainWindow() or standardWindows(app)[1]
    if win then
      focusWindow(win)
      return
    end
  end

  launchApp(spec)  -- ウィンドウが1枚も無い → 起動しなおして開かせる
end

-- ---------------------------------------------------------------------
-- タイリング
-- ---------------------------------------------------------------------

-- 画面の作業領域（メニューバー・Dock を除く）から外周の隙間を除いた領域
local function workArea(screen)
  local f = screen:frame()
  return { x = f.x + GAP, y = f.y + GAP, w = f.w - GAP * 2, h = f.h - GAP * 2 }
end

local function isTileable(w, screen)
  if not (w:isStandard() and w:isVisible()) or w:isFullScreen() then return false end
  if M.floating[w:id()] then return false end
  local ws = w:screen()
  if not ws or ws:id() ~= screen:id() then return false end
  local app = w:application()
  return not (app and EXCLUDE_APPS[app:bundleID() or ""])
end

-- 今のデスクトップ・指定画面にある整列対象のウィンドウを、M.order の順で返す。
-- M.order に無い（新しい）ウィンドウは末尾に足す。
local function tileableWindows(screen)
  local byId, fresh = {}, {}
  for _, w in ipairs(hs.window.orderedWindows()) do   -- 現デスクトップ・前面から順
    if isTileable(w, screen) then
      byId[w:id()] = w
      fresh[#fresh + 1] = w
    end
  end

  local result, used = {}, {}
  for _, id in ipairs(M.order) do
    if byId[id] and not used[id] then
      result[#result + 1] = byId[id]
      used[id] = true
    end
  end
  for _, w in ipairs(fresh) do
    if not used[w:id()] then result[#result + 1] = w end
  end
  return result
end

-- M.order の先頭側を ids の並びにそろえる（ids に無いIDは後ろに残す）
local function setOrderFront(ids)
  local seen, newOrder = {}, {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      newOrder[#newOrder + 1] = id
      seen[id] = true
    end
  end
  for _, id in ipairs(M.order) do
    if not seen[id] and hs.window.get(id) then newOrder[#newOrder + 1] = id end
  end
  M.order = newOrder
end

-- レイアウトごとに n 枚分の枠を計算する
local LAYOUT_FRAMES = {
  -- メイン+スタック: 左にメイン1枚、右に残りを縦に積む
  tall = function(a, n)
    if n == 1 then return { a } end
    local mainW = math.floor(a.w * M.ratio - GAP / 2)
    local stackX = a.x + mainW + GAP
    local stackW = a.w - mainW - GAP
    local stackH = (a.h - GAP * (n - 2)) / (n - 1)
    local frames = { { x = a.x, y = a.y, w = mainW, h = a.h } }
    for i = 1, n - 1 do
      frames[#frames + 1] = { x = stackX, y = a.y + (stackH + GAP) * (i - 1), w = stackW, h = stackH }
    end
    return frames
  end,
  -- 横等分
  columns = function(a, n)
    local colW = (a.w - GAP * (n - 1)) / n
    local frames = {}
    for i = 1, n do
      frames[i] = { x = a.x + (colW + GAP) * (i - 1), y = a.y, w = colW, h = a.h }
    end
    return frames
  end,
  -- 全最大化（モノクル）
  monocle = function(a, n)
    local frames = {}
    for i = 1, n do frames[i] = { x = a.x, y = a.y, w = a.w, h = a.h } end
    return frames
  end,
}

-- 直前の整列から、ウィンドウの顔ぶれと位置が変わっていないか。
-- ターミナル等は文字単位でしかリサイズできないので、多少のずれは許容する。
local TILE_TOLERANCE = 40

local function stillTiled(screen, wins)
  local last = M.lastTile
  if not last or last.screen ~= screen:id() or #wins ~= #last.ids then return false end
  for i, w in ipairs(wins) do
    if w:id() ~= last.ids[i] then return false end
    local f, t = w:frame(), last.frames[i]
    if math.abs(f.x - t.x) > TILE_TOLERANCE or math.abs(f.y - t.y) > TILE_TOLERANCE
      or math.abs(f.w - t.w) > TILE_TOLERANCE or math.abs(f.h - t.h) > TILE_TOLERANCE then
      return false
    end
  end
  return true
end

-- 指定画面を今のレイアウトで整列する
local function tile(screen)
  screen = screen or hs.screen.mainScreen()
  local wins = tileableWindows(screen)
  if #wins == 0 then return end

  local name = M.layouts[M.layout]
  local frames = LAYOUT_FRAMES[name](workArea(screen), #wins)
  local ids = {}
  for i, w in ipairs(wins) do
    w:setFrame(frames[i], 0)
    ids[i] = w:id()
  end
  setOrderFront(ids)
  M.lastTile = { screen = screen:id(), ids = ids, frames = frames }

  -- モノクルは重なるので、フォーカス中のウィンドウを前面に保つ
  if name == "monocle" then
    local fw = hs.window.focusedWindow()
    if fw then fw:raise() end
  end
end

local function focusedScreen()
  local w = hs.window.focusedWindow()
  return (w and w:screen()) or hs.screen.mainScreen()
end

-- ⌥+Enter: 整列。整列済みのまま押されたら次のレイアウトへ
local function tileOrCycleLayout()
  local screen = focusedScreen()
  if stillTiled(screen, tileableWindows(screen)) then
    M.layout = M.layout % #M.layouts + 1
    hs.alert.show("レイアウト: " .. M.layouts[M.layout], 0.6)
  end
  tile(screen)
end

-- ⌥+⇧+Enter: フォーカス中のウィンドウをメインにして整列
local function promoteToMain()
  local w = hs.window.focusedWindow()
  if not w then return end
  M.floating[w:id()] = nil
  setOrderFront({ w:id() })
  tile(w:screen())
end

-- ⌥+[ / ]: メイン領域の幅を変える
local function adjustRatio(delta)
  M.ratio = math.max(0.2, math.min(0.8, M.ratio + delta))
  hs.alert.show(string.format("メイン幅 %d%%", math.floor(M.ratio * 100 + 0.5)), 0.5)
  tile(focusedScreen())
end

-- ⌥+⇧+Space: フロート切替
local function toggleFloat()
  local w = hs.window.focusedWindow()
  if not w then return end
  local id = w:id()
  M.floating[id] = not M.floating[id] or nil
  hs.alert.show(M.floating[id] and "フロート" or "タイル", 0.5)
  tile(w:screen())
end

-- ---------------------------------------------------------------------
-- 方向フォーカス / 入替
-- ---------------------------------------------------------------------

local DIRECTIONS = { h = "West", j = "South", k = "North", l = "East" }

local function focusDirection(dir)
  local w = hs.window.focusedWindow()
  if w then w["focusWindow" .. dir](w, nil, true, true) end
end

local function swapDirection(dir)
  local w = hs.window.focusedWindow()
  if not w then return end
  local other = w["windowsTo" .. dir](w, nil, true, true)[1]
  if not other then return end

  local f1, f2 = w:frame(), other:frame()
  w:setFrame(f2, 0)
  other:setFrame(f1, 0)

  -- 整列順も入れ替えて、次の整列で元に戻らないようにする
  local ids = tileableWindows(w:screen())
  local order = {}
  for i, x in ipairs(ids) do order[i] = x:id() end
  local a, b
  for i, id in ipairs(order) do
    if id == w:id() then a = i elseif id == other:id() then b = i end
  end
  if a and b then
    order[a], order[b] = order[b], order[a]
    setOrderFront(order)
  end
  M.lastTile = nil
  w:focus()
end

-- ---------------------------------------------------------------------
-- アプリのまとまり（⌥+数字）
-- ---------------------------------------------------------------------

local GROUP_LAUNCH_TIMEOUT = 3

-- まとまりに含まれるアプリの bundle ID と名前の集合
local function groupMembers(n)
  local set = {}
  for _, key in ipairs(GROUPS[n] or {}) do
    local spec = APPS[key]
    if spec then
      for _, id in ipairs(spec.bundleIDs or {}) do set[id] = true end
      set[spec.name] = true
    end
  end
  return set
end

local function inGroup(members, app)
  return app and (members[app:bundleID() or ""] or members[app:name() or ""])
end

-- 群のウィンドウを、群の定義順（先頭アプリがメイン）で返す
local function groupWindows(n, screen)
  local wins = {}
  for _, key in ipairs(GROUPS[n] or {}) do
    local app = APPS[key] and runningApp(APPS[key])
    if app then
      for _, w in ipairs(app:allWindows()) do
        if isTileable(w, screen) then wins[#wins + 1] = w end
      end
    end
  end
  return wins
end

local function showGroup(n)
  local members = groupMembers(n)
  local screen = focusedScreen()

  -- 続けて押した: 群の中でフォーカス巡回
  local front = hs.application.frontmostApplication()
  if M.activeGroup == n and inGroup(members, front) then
    local wins = {}
    for _, w in ipairs(tileableWindows(screen)) do
      if inGroup(members, w:application()) then wins[#wins + 1] = w end
    end
    focusNextIn(wins)
    return
  end
  M.activeGroup = n

  -- 群のアプリを起動 / 再表示し、それ以外の通常アプリを隠す
  for _, key in ipairs(GROUPS[n] or {}) do
    local spec = APPS[key]
    local app = spec and runningApp(spec)
    if app then
      app:unhide()
    elseif spec then
      launchApp(spec)
    end
  end
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 and not inGroup(members, app)
      and app:bundleID() ~= "org.hammerspoon.Hammerspoon" then
      app:hide()
    end
  end

  -- 起動直後のアプリはウィンドウが遅れて出るので、全アプリのウィンドウがそろうのを待つ
  local deadline = hs.timer.secondsSinceEpoch() + GROUP_LAUNCH_TIMEOUT
  hs.timer.waitUntil(
    function()
      if hs.timer.secondsSinceEpoch() > deadline then return true end
      for _, key in ipairs(GROUPS[n] or {}) do
        local app = APPS[key] and runningApp(APPS[key])
        if not app or not app:mainWindow() then return false end
      end
      return true
    end,
    function()
      local wins = groupWindows(n, screen)
      local ids = {}
      for i, w in ipairs(wins) do ids[i] = w:id() end
      setOrderFront(ids)
      tile(screen)
      if wins[1] then wins[1]:focus() end
    end,
    0.1)
end

-- ---------------------------------------------------------------------
-- スナップ（⌃⌥+矢印）
-- ---------------------------------------------------------------------

local SNAP_RATIOS = { 1 / 2, 2 / 3, 1 / 3 }
local SNAP_TOLERANCE = 20

local function snapFrame(a, side, r)
  if side == "left"  then return { x = a.x, y = a.y, w = a.w * r, h = a.h } end
  if side == "right" then return { x = a.x + a.w * (1 - r), y = a.y, w = a.w * r, h = a.h } end
  if side == "up"    then return { x = a.x, y = a.y, w = a.w, h = a.h * r } end
  return { x = a.x, y = a.y + a.h * (1 - r), w = a.w, h = a.h * r }  -- down
end

local function near(f, t)
  return math.abs(f.x - t.x) <= SNAP_TOLERANCE and math.abs(f.y - t.y) <= SNAP_TOLERANCE
    and math.abs(f.w - t.w) <= SNAP_TOLERANCE and math.abs(f.h - t.h) <= SNAP_TOLERANCE
end

-- 同じ向きで続けて押すと 1/2 → 2/3 → 1/3 と幅が変わる
local function snap(side)
  local w = hs.window.focusedWindow()
  if not w then return end
  local a = workArea(w:screen())
  local cur = w:frame()
  local nextIdx = 1
  for i, r in ipairs(SNAP_RATIOS) do
    if near(cur, snapFrame(a, side, r)) then nextIdx = i % #SNAP_RATIOS + 1 break end
  end
  w:setFrame(snapFrame(a, side, SNAP_RATIOS[nextIdx]), 0)
end

local function maximize()
  local w = hs.window.focusedWindow()
  if w then w:setFrame(workArea(w:screen()), 0) end
end

local function center()
  local w = hs.window.focusedWindow()
  if not w then return end
  local a = workArea(w:screen())
  w:setFrame({ x = a.x + a.w * 0.15, y = a.y + a.h * 0.1, w = a.w * 0.7, h = a.h * 0.8 }, 0)
end

-- ---------------------------------------------------------------------
-- 自動整列（⌃⌥+t）
-- ---------------------------------------------------------------------
-- ウィンドウの生成・破棄・最小化に合わせて整列し直す。macOS のイベントは揺れるので、
-- 短い遅延でまとめてから 1 回だけ整列する。

M.autoTimer = M.autoTimer or hs.timer.delayed.new(0.3, function() tile(focusedScreen()) end)

local function setAutoTile(on)
  if M.autoFilter then
    M.autoFilter:unsubscribeAll()
    M.autoFilter = nil
  end
  M.autoTile = on
  if on then
    M.autoFilter = hs.window.filter.new(nil, "tiling.auto"):setCurrentSpace(true)
    M.autoFilter:subscribe({
      hs.window.filter.windowCreated,
      hs.window.filter.windowDestroyed,
      hs.window.filter.windowMinimized,
      hs.window.filter.windowUnminimized,
    }, function() M.autoTimer:start() end)
  end
end

local function toggleAutoTile()
  setAutoTile(not M.autoTile)
  hs.alert.show(M.autoTile and "自動整列 ON" or "自動整列 OFF", 0.6)
  if M.autoTile then tile(focusedScreen()) end
end

-- ---------------------------------------------------------------------
-- ホットキー
-- ---------------------------------------------------------------------

if M.hotkeys then
  for _, hk in ipairs(M.hotkeys) do hk:delete() end
end
M.hotkeys = {}

local function bind(mods, key, fn)
  M.hotkeys[#M.hotkeys + 1] = hs.hotkey.bind(mods, key, fn)
end

-- アプリ
for key, appKey in pairs(APP_KEYS) do
  bind(MOD, key, function()
    M.activeGroup = nil
    focusApp(APPS[appKey])
  end)
end

-- まとまり
for n in pairs(GROUPS) do
  bind(MOD, tostring(n), function() showGroup(n) end)
end

-- 方向フォーカス / 入替
for key, dir in pairs(DIRECTIONS) do
  bind(MOD, key, function() focusDirection(dir) end)
  bind(MOD_SHIFT, key, function() swapDirection(dir) end)
end

-- 整列
bind(MOD, "return", tileOrCycleLayout)
bind(MOD_SHIFT, "return", promoteToMain)
bind(MOD, "[", function() adjustRatio(-RATIO_STEP) end)
bind(MOD, "]", function() adjustRatio(RATIO_STEP) end)
bind(MOD_SHIFT, "space", toggleFloat)

-- スナップ
bind(SNAP_MOD, "left",  function() snap("left") end)
bind(SNAP_MOD, "right", function() snap("right") end)
bind(SNAP_MOD, "up",    function() snap("up") end)
bind(SNAP_MOD, "down",  function() snap("down") end)
bind(SNAP_MOD, "return", maximize)
bind(SNAP_MOD, "c", center)
bind(SNAP_MOD, "g", function() hs.grid.show() end)
bind(SNAP_MOD, "t", toggleAutoTile)
bind(SNAP_MOD, "r", function() hs.reload() end)

hs.grid.setGrid("6x4")
hs.grid.setMargins(GAP .. "x" .. GAP)

setAutoTile(M.autoTile or false)
hs.alert.show("タイル型WM 読み込み完了", 0.8)
