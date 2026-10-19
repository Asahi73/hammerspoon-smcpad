-- =====================================================================
-- Macエンジニア向け設定 (Hammerspoon)
-- =====================================================================
-- 右⌘ を Hyper キーとして扱い、次の機能を提供する。
--   1. アプリの起動 / 前面化 / 非表示
--   2. コマンドパレット
--   3. クリップボード履歴
--   4. 設定ファイル保存時の自動リロード
--   5. 割り当て一覧（チートシート）
--   6. ウィンドウ配置（左半分 / 右半分 / 最大化）
--   7. 直前のアプリへ戻る
--   8. ブラウザのページを Markdown リンクでコピー
--   9. アプリごとの入力ソース自動切替
--  10. 指定 Wi-Fi から切断されたら VPN アプリを起動
--  11. 外部モニタ接続時のウィンドウ配置
--  12. スリープ復帰時のアプリ前面化
--  13. 長いコマンドの完了通知（hs コマンドから呼ぶ）
--
-- 導入方法・キー割り当て・カスタマイズは同じフォルダの README.md を参照。
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- 右⌘ をこの秒数だけ単独で押し続けると割り当て一覧を出す
local CHEAT_HOLD_SEC = 1.0

-- クリップボード履歴の最大件数
local CLIP_MAX = 30

-- Hyper + キー → アプリ。bundleIDs を上から順に試し、無ければ name で起動する。
local APPS = {
  { key = "e", desc = "エディタ",     name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  { key = "t", desc = "ターミナル",   name = "Terminal",           bundleIDs = { "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal" } },
  { key = "b", desc = "ブラウザ",     name = "Google Chrome",      bundleIDs = { "com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari" } },
  { key = "s", desc = "Slack",        name = "Slack",              bundleIDs = { "com.tinyspeck.slackmacgap" } },
  { key = "w", desc = "メモ",         name = "Notes",              bundleIDs = { "com.apple.Notes" } },
  { key = "f", desc = "Finder",       name = "Finder",             bundleIDs = { "com.apple.finder" } },
}

-- コマンドパレットの項目。kind は url / snippet / shell のいずれか。
-- （APPS に書いたアプリは自動でパレットにも並ぶ）
local PALETTE = {
  { kind = "url",     text = "GitHub",                 value = "https://github.com" },
  { kind = "url",     text = "Hammerspoon ドキュメント", value = "https://www.hammerspoon.org/docs/" },
  { kind = "snippet", text = "LGTM",                   value = "LGTM :+1:" },
  { kind = "snippet", text = "コードブロック",          value = "```\n\n```" },
  { kind = "shell",   text = "IPアドレスを表示",        value = "ipconfig getifaddr en0" },
  { kind = "shell",   text = "Homebrew を更新",         value = "brew update && brew upgrade" },
  { kind = "shell",   text = "Downloads を開く",        value = "open ~/Downloads" },
}

-- アプリが前面に来たときの入力ソース。"en" = 英数、"ja" = かな
local INPUT_BY_APP = {
  ["com.mitchellh.ghostty"]     = "en",
  ["com.googlecode.iterm2"]     = "en",
  ["com.apple.Terminal"]        = "en",
  ["com.microsoft.VSCode"]      = "en",
  ["com.tinyspeck.slackmacgap"] = "ja",
}

-- この SSID のいずれかから切断されたら、VPN アプリを起動する
local WIFI_VPN = {
  ssids = { "Office-WiFi" },
  app   = { name = "Tunnelblick", bundleIDs = { "net.tunnelblick.tunnelblick" } },
}

-- 外部モニタ接続時に、外部モニタへ移して配置するアプリ。position は left / right / max
local MONITOR_LAYOUT = {
  { position = "left",  app = { name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } } },
  { position = "right", app = { name = "Google Chrome",      bundleIDs = { "com.google.Chrome" } } },
}

-- スリープ復帰時に前面化するアプリ
local WAKE_APP = { name = "Slack", bundleIDs = { "com.tinyspeck.slackmacgap" } }

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

-- watcher 等は変数から参照が消えるとGCで止まるので、ここにまとめて保持する
macEngineer = {}

-- ---------------------------------------------------------------------
-- Hyperキー（右⌘）
-- ---------------------------------------------------------------------
-- hs.hotkey は左右の ⌘ を区別できないので、hs.eventtap でキー入力を直接見る。
--   ・右⌘ の押下/解放は flagsChanged イベントの「右⌘ビット」で判定する
--   ・右⌘ を押している間のキー入力のうち、割り当てたキーだけを横取りする
-- 判定はイベント自身の右⌘ビットで行うので、この設定が送る ⌘V 等の合成キーには反応しない。
local RIGHT_CMD_BIT = hs.eventtap.event.rawFlagMasks.deviceRightCommand
local evt = hs.eventtap.event.types

local hyperBindings = {}   -- チートシート用 { key, desc }（登録順）
local hyperActions  = {}   -- keycode → 処理
local hyperDown     = false
local hyperUsed     = false
local holdTimer     = nil
local swallowed     = {}   -- 横取りした keyDown の keycode（対応する keyUp も捨てる）
local showCheatsheet, hideCheatsheet   -- 5. で定義

local function hyperBind(key, desc, fn)
  hyperBindings[#hyperBindings + 1] = { key = key, desc = desc }
  hyperActions[hs.keycodes.map[key]] = fn
end

local function isRightCmd(e)
  return (e:rawFlags() & RIGHT_CMD_BIT) ~= 0
end

macEngineer.hyperTap = hs.eventtap.new({ evt.flagsChanged, evt.keyDown, evt.keyUp }, function(e)
  local t, code = e:getType(), e:getKeyCode()

  if t == evt.flagsChanged then
    local down = isRightCmd(e)
    if down and not hyperDown then
      hyperDown, hyperUsed = true, false
      holdTimer = hs.timer.doAfter(CHEAT_HOLD_SEC, function()
        if hyperDown and not hyperUsed then showCheatsheet() end
      end)
    elseif not down and hyperDown then
      hyperDown = false
      if holdTimer then holdTimer:stop(); holdTimer = nil end
      hideCheatsheet()
    end
    return false
  end

  if t == evt.keyUp then
    if swallowed[code] then swallowed[code] = nil; return true end
    return false
  end

  -- keyDown
  if not (hyperDown and isRightCmd(e)) then return false end
  hyperUsed = true
  local fn = hyperActions[code]
  if not fn then return false end               -- 未割り当ては普通の ⌘ ショートカットとして通す
  swallowed[code] = true
  -- キーリピートは無視。タップの中で重い処理をしないよう、処理は次のループで実行する
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then
    hs.timer.doAfter(0, fn)
  end
  return true
end):start()

-- 長時間の処理などで macOS にタップを止められることがあるので、止まっていたら再開する
macEngineer.hyperWatchdog = hs.timer.doEvery(5, function()
  if not macEngineer.hyperTap:isEnabled() then macEngineer.hyperTap:start() end
end)

-- ---------------------------------------------------------------------
-- 共通: 貼り付け
-- ---------------------------------------------------------------------
-- chooser を閉じた直後は元のアプリにフォーカスが戻りきっていないので少し待つ
local function paste(text)
  hs.pasteboard.setContents(text)
  hs.timer.doAfter(0.1, function() hs.eventtap.keyStroke({ "cmd" }, "v") end)
end

-- ---------------------------------------------------------------------
-- 1. アプリの起動/前面化/隠す
-- ---------------------------------------------------------------------
local function runningApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    local app = hs.application.get(id)
    if app then return app end
  end
  return hs.application.get(spec.name)
end

local function launchApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    if hs.application.launchOrFocusByBundleID(id) then return true end
  end
  if hs.application.launchOrFocus(spec.name) then return true end
  hs.alert.show("起動できない: " .. spec.name)
  return false
end

local function toggleApp(spec)
  local app = runningApp(spec)
  if app and app:isFrontmost() then
    app:hide()
  else
    launchApp(spec)
  end
end

for _, spec in ipairs(APPS) do
  hyperBind(spec.key, spec.desc, function() toggleApp(spec) end)
end

-- ---------------------------------------------------------------------
-- 2. コマンドパレット
-- ---------------------------------------------------------------------
local function runShell(cmd)
  -- ログインシェルで実行し、PATH（Homebrew 等）を通す
  hs.task.new("/bin/zsh", function(code, out, err)
    local msg = (out ~= "" and out or err):gsub("%s+$", "")
    if msg == "" then msg = (code == 0) and "完了" or ("失敗 (" .. code .. ")") end
    hs.alert.show(msg:sub(1, 200), 4)
  end, { "-lc", cmd }):start()
end

local KIND_LABEL = { url = "URL", snippet = "スニペット", shell = "シェル", app = "アプリ" }

local palette = hs.chooser.new(function(choice)
  if not choice then return end
  if choice.kind == "url" then
    hs.urlevent.openURL(choice.value)
  elseif choice.kind == "snippet" then
    paste(choice.value)
  elseif choice.kind == "shell" then
    runShell(choice.value)
  elseif choice.kind == "app" then
    launchApp(APPS[choice.value])
  end
end)
palette:searchSubText(true)

local function paletteChoices()
  local items = {}
  for _, p in ipairs(PALETTE) do
    items[#items + 1] = { text = p.text, subText = KIND_LABEL[p.kind] .. ": " .. p.value:gsub("\n", " "),
                          kind = p.kind, value = p.value }
  end
  for i, spec in ipairs(APPS) do
    items[#items + 1] = { text = spec.desc, subText = "アプリ: " .. spec.name, kind = "app", value = i }
  end
  return items
end

hyperBind("space", "コマンドパレット", function()
  palette:choices(paletteChoices())
  palette:show()
end)

-- ---------------------------------------------------------------------
-- 3. クリップボード履歴
-- ---------------------------------------------------------------------
-- 履歴は hs.settings に保存するので、Hammerspoon を再起動しても残る。
local CLIP_KEY = "macEngineer.clipHistory"
local clipHistory = hs.settings.get(CLIP_KEY) or {}

-- パスワードマネージャ等が「記録しないで」と付ける目印
local function isConcealed()
  for _, t in ipairs(hs.pasteboard.contentTypes() or {}) do
    if t == "org.nspasteboard.ConcealedType" or t == "org.nspasteboard.TransientType" then return true end
  end
  return false
end

macEngineer.clipWatcher = hs.pasteboard.watcher.new(function(text)
  if not text or text == "" or isConcealed() then return end
  for i, v in ipairs(clipHistory) do
    if v == text then table.remove(clipHistory, i) break end   -- 重複は先頭へ移動
  end
  table.insert(clipHistory, 1, text)
  while #clipHistory > CLIP_MAX do table.remove(clipHistory) end
  hs.settings.set(CLIP_KEY, clipHistory)
end)

local clipChooser = hs.chooser.new(function(choice)
  if choice then paste(choice.full) end
end)

hyperBind("v", "クリップボード履歴", function()
  local items = {}
  for _, t in ipairs(clipHistory) do
    items[#items + 1] = { text = t:gsub("%s+", " "):sub(1, 80), full = t }
  end
  clipChooser:choices(items)
  clipChooser:show()
end)

-- ---------------------------------------------------------------------
-- 4. 保存で自動リロード
-- ---------------------------------------------------------------------
-- install.sh でシンボリックリンクにしている場合、編集されるのはリンク先（リポジトリ内）の
-- ファイルなので、~/.hammerspoon だけでなくリンク先のフォルダも監視する。
local function onChange(files)
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      hs.reload()
      return
    end
  end
end

macEngineer.reloadWatchers = { hs.pathwatcher.new(hs.configdir, onChange):start() }
local realInit = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua")
local realDir = realInit and realInit:match("^(.*)/[^/]+$")
if realDir and realDir ~= hs.configdir then
  table.insert(macEngineer.reloadWatchers, hs.pathwatcher.new(realDir, onChange):start())
end

-- ---------------------------------------------------------------------
-- 5. チートシート（右⌘ の長押し中だけ表示）
-- ---------------------------------------------------------------------
local KEY_LABEL = { space = "Space", tab = "Tab" }
local cheatAlert = nil

function showCheatsheet()
  local lines = { "右⌘ +" }
  for _, b in ipairs(hyperBindings) do
    lines[#lines + 1] = string.format("  %-6s %s", KEY_LABEL[b.key] or b.key:upper(), b.desc)
  end
  lines[#lines + 1] = "  長押し  この一覧"
  cheatAlert = hs.alert.show(table.concat(lines, "\n"),
    { textFont = "Menlo", textSize = 18, atScreenEdge = 0 }, hs.screen.mainScreen(), true)   -- 秒数に数値以外を渡すと消すまで表示
end

function hideCheatsheet()
  if cheatAlert then
    hs.alert.closeSpecific(cheatAlert)
    cheatAlert = nil
  end
end

-- ---------------------------------------------------------------------
-- 6. ウィンドウ配置
-- ---------------------------------------------------------------------
-- 右⌘ を押さえた右手の指がホーム段にあるので、H / K / L を使う。
local UNITS = {
  left  = { x = 0,   y = 0, w = 0.5, h = 1 },
  right = { x = 0.5, y = 0, w = 0.5, h = 1 },
  max   = { x = 0,   y = 0, w = 1,   h = 1 },
}

local function placeFocused(position)
  local win = hs.window.focusedWindow()
  if win then win:moveToUnit(UNITS[position], 0) end
end

hyperBind("h", "左半分", function() placeFocused("left") end)
hyperBind("l", "右半分", function() placeFocused("right") end)
hyperBind("k", "最大化", function() placeFocused("max") end)

-- ---------------------------------------------------------------------
-- 7. 直前のアプリへ戻る ／ 9. 入力ソース自動切替
-- ---------------------------------------------------------------------
-- どちらも「アプリが前面に来た」イベントで動くので、watcher を1つにまとめる。
-- 入力ソースは JIS キーボードの英数 / かなキーを送って切り替える。
-- 入力ソースIDを直接指定する方式と違い、ことえり・Google 日本語入力などIMEを問わず動く。
local HS_BUNDLE = "org.hammerspoon.Hammerspoon"
local KEY_EISU, KEY_KANA = 102, 104
local currentApp  = hs.application.frontmostApplication()
local previousApp = nil

local function setInput(kind)
  local code = (kind == "ja") and KEY_KANA or KEY_EISU
  hs.eventtap.event.newKeyEvent({}, code, true):post()
  hs.eventtap.event.newKeyEvent({}, code, false):post()
end

macEngineer.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event ~= hs.application.watcher.activated or not app then return end
  local id = app:bundleID()
  -- パレット等を開くと Hammerspoon 自身が前面に来るので、履歴にも入力切替にも含めない
  if id == HS_BUNDLE then return end
  if not currentApp or currentApp:pid() ~= app:pid() then
    previousApp, currentApp = currentApp, app
  end
  if INPUT_BY_APP[id] then setInput(INPUT_BY_APP[id]) end
end):start()

hyperBind("tab", "直前のアプリ", function()
  if previousApp and previousApp:isRunning() then previousApp:activate() end
end)

-- ---------------------------------------------------------------------
-- 8. Markdown リンクのコピー
-- ---------------------------------------------------------------------
-- ブラウザごとに AppleScript でタイトルと URL を取る（初回は macOS が操作の許可を求める）。
local BROWSER_SCRIPTS = {
  ["com.google.Chrome"]          = 'tell application "Google Chrome" to return {title, URL} of active tab of front window',
  ["company.thebrowser.Browser"] = 'tell application "Arc" to return {title, URL} of active tab of front window',
  ["com.apple.Safari"]           = 'tell application "Safari" to return {name, URL} of front document',
}

hyperBind("r", "ページをMDリンクでコピー", function()
  local app = hs.application.frontmostApplication()
  local script = app and BROWSER_SCRIPTS[app:bundleID()]
  if not script then
    hs.alert.show("ブラウザが前面にない")
    return
  end
  local ok, res = hs.osascript.applescript(script)
  if not ok or type(res) ~= "table" or not res[2] then
    hs.alert.show("ページ情報を取得できない")
    return
  end
  -- タイトル中の [ ] はリンク記法を壊すのでエスケープする
  local link = string.format("[%s](%s)", tostring(res[1]):gsub("[%[%]]", "\\%0"), res[2])
  hs.pasteboard.setContents(link)
  hs.alert.show("コピー: " .. link)
end)

-- ---------------------------------------------------------------------
-- 10. Wi-Fi 切断で VPN アプリを起動
-- ---------------------------------------------------------------------
-- 直前の SSID を覚えておき、「指定 SSID → それ以外（未接続を含む）」の変化だけを拾う。
local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local lastSSID = hs.wifi.currentNetwork()
macEngineer.wifiWatcher = hs.wifi.watcher.new(function()
  local ssid = hs.wifi.currentNetwork()
  if ssid == lastSSID then return end
  if contains(WIFI_VPN.ssids, lastSSID) and not contains(WIFI_VPN.ssids, ssid) then
    hs.alert.show("Wi-Fi から切断: VPN を起動")
    launchApp(WIFI_VPN.app)
  end
  lastSSID = ssid
end):start()

-- ---------------------------------------------------------------------
-- 11. 外部モニタ接続時のウィンドウ配置
-- ---------------------------------------------------------------------
-- 画面数が増えたときだけ動く。接続直後は画面の並びが確定していないので少し待つ。
local function isBuiltin(screen)
  local name = screen:name() or ""
  return name:match("Built%-in") ~= nil or name:match("内蔵") ~= nil
end

local function externalScreen()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if not isBuiltin(screen) then return screen end
  end
  return nil
end

local function applyMonitorLayout()
  local ext = externalScreen()
  if not ext then return end
  for _, item in ipairs(MONITOR_LAYOUT) do
    local app = runningApp(item.app)
    for _, win in ipairs(app and app:allWindows() or {}) do
      if win:isStandard() then
        win:moveToScreen(ext, false, true, 0)
        win:moveToUnit(UNITS[item.position], 0)
      end
    end
  end
end

local screenCount = #hs.screen.allScreens()
macEngineer.screenWatcher = hs.screen.watcher.new(function()
  local count = #hs.screen.allScreens()
  if count > screenCount then hs.timer.doAfter(2, applyMonitorLayout) end
  screenCount = count
end):start()

-- ---------------------------------------------------------------------
-- 12. スリープ復帰時のアプリ前面化
-- ---------------------------------------------------------------------
-- 復帰直後はロック画面なので、ロック解除のタイミングでも前面化する。
macEngineer.wakeWatcher = hs.caffeinate.watcher.new(function(event)
  local w = hs.caffeinate.watcher
  if event == w.systemDidWake or event == w.screensDidUnlock then
    launchApp(WAKE_APP)
  end
end):start()

-- ---------------------------------------------------------------------
-- 13. 長いコマンドの完了通知
-- ---------------------------------------------------------------------
-- hs コマンド（hs.ipc）から notifyDone(終了コード, ラベル) を呼ぶ。
-- hs -c から見えるよう、関数はグローバルに置く。
require("hs.ipc")

function notifyDone(status, label)
  status = tonumber(status) or 0
  local title = (status == 0) and "コマンド完了" or ("コマンド失敗 (" .. status .. ")")
  hs.notify.new({
    title = title,
    informativeText = label or "",
    soundName = (status == 0) and "Glass" or "Basso",
  }):send()
  hs.alert.show(title .. (label and label ~= "" and (": " .. label) or ""), 3)
end

hs.alert.show("Hammerspoon: 設定を読み込みました")
