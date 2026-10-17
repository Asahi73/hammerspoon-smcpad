-- =====================================================================
-- Macエンジニア向け Hammerspoon 設定（1ファイル完結）
-- =====================================================================
-- Caps Lock を Hyper キーにして、次の5つを使えるようにする。Karabiner は不要。
--   1. Hyper + 文字   アプリを起動/前面化（前面ならもう一度押すと隠す）
--   2. Hyper + Space  コマンドパレット（URL・スニペット・シェルコマンド・アプリ）
--   3. Hyper + V      クリップボード履歴
--   4. 保存で自動リロード
--   5. Hyper + /      割り当て一覧（チートシート）
--
-- 単押しの Caps Lock は Escape になる（TAP_ESCAPE で切替）。
--
-- 使い方（既存の ~/.hammerspoon/init.lua は退避してから）:
--   ln -s "$PWD/hammerspoon/variants/mac-engineer/init.lua" ~/.hammerspoon/init.lua
-- 権限: システム設定 → プライバシーとセキュリティ → アクセシビリティ で Hammerspoon をオン
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- Caps Lock を単押ししたときに Escape を送るか
local TAP_ESCAPE = true

-- クリップボード履歴の最大件数
local CLIP_MAX = 30

-- Hyper + キー → アプリ。bundleIDs を上から順に試し、無ければ name で起動する。
-- bundle ID の調べ方: osascript -e 'id of app "Slack"'
local APPS = {
  { key = "e", desc = "エディタ",     name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  { key = "t", desc = "ターミナル",   name = "Terminal",           bundleIDs = { "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal" } },
  { key = "b", desc = "ブラウザ",     name = "Google Chrome",      bundleIDs = { "com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari" } },
  { key = "s", desc = "Slack",        name = "Slack",              bundleIDs = { "com.tinyspeck.slackmacgap" } },
  { key = "n", desc = "メモ",         name = "Notes",              bundleIDs = { "com.apple.Notes" } },
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

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

-- watcher 等は変数から参照が消えるとGCで止まるので、ここにまとめて保持する
macEngineer = {}

-- ---------------------------------------------------------------------
-- Hyperキー
-- ---------------------------------------------------------------------
-- macOS 標準の hidutil で Caps Lock を F18 に割り当て、F18 を押している間だけ
-- 有効になるモーダルを Hyper として使う。hidutil の割り当ては再起動で消えるので、
-- Hammerspoon の起動（=ログイン時）ごとに設定し直す。
-- 注意: hidutil の UserKeyMapping は上書きなので、他に hidutil で割り当てていれば消える。
-- 元に戻す: hidutil property --set '{"UserKeyMapping":[]}'
local CAPS_LOCK = 0x700000039
local F18       = 0x70000006D

local function remapCapsLock()
  local json = string.format(
    '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x%X,"HIDKeyboardModifierMappingDst":0x%X}]}',
    CAPS_LOCK, F18)
  local _, ok = hs.execute("/usr/bin/hidutil property --set '" .. json .. "'")
  if not ok then print("[hyper] hidutil での Caps Lock 割り当てに失敗") end
end

local hyper = hs.hotkey.modal.new()
local hyperUsed = false          -- Hyper 中に何か押したか（単押し判定用）
local hyperBindings = {}         -- チートシート用 { key, desc }

local function hyperBind(key, desc, fn)
  hyperBindings[#hyperBindings + 1] = { key = key, desc = desc }
  hyper:bind({}, key, function()
    hyperUsed = true
    fn()
  end)
end

remapCapsLock()
macEngineer.hyperKey = hs.hotkey.bind({}, "f18",
  function()
    hyperUsed = false
    hyper:enter()
  end,
  function()
    hyper:exit()
    if TAP_ESCAPE and not hyperUsed then hs.eventtap.keyStroke({}, "escape", 0) end
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
-- 5. チートシート
-- ---------------------------------------------------------------------
local KEY_LABEL = { space = "Space" }
local cheatAlert = nil

hyperBind("/", "この一覧", function()
  if cheatAlert then
    hs.alert.closeSpecific(cheatAlert)
    cheatAlert = nil
    return
  end
  local lines = { "Hyper (Caps Lock) +" }
  for _, b in ipairs(hyperBindings) do
    lines[#lines + 1] = string.format("  %-6s %s", KEY_LABEL[b.key] or b.key:upper(), b.desc)
  end
  cheatAlert = hs.alert.show(table.concat(lines, "\n"),
    { textFont = "Menlo", textSize = 18, atScreenEdge = 0 }, hs.screen.mainScreen(), 6)
  hs.timer.doAfter(6, function() cheatAlert = nil end)
end)

hs.alert.show("Hammerspoon: 設定を読み込みました")
