#!/bin/sh
# Windows互換モードのインストール / アンインストール
#   ./install.sh              … 今の ~/.hammerspoon/init.lua を退避して、このモードに切り替える
#   ./install.sh --uninstall  … 退避しておいた元の init.lua に戻す
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/init.lua"
DST="$HOME/.hammerspoon/init.lua"
BAK="$HOME/.hammerspoon/init.lua.before-wincompat"

reload() {
  # Hammerspoon が起動中で hs コマンドが入っていれば自動で再読み込みする
  if command -v hs >/dev/null 2>&1 && pgrep -q Hammerspoon; then
    hs -c 'hs.reload()' >/dev/null 2>&1 || true
    echo "Hammerspoon を再読み込みしました。"
  else
    echo "Hammerspoon のコンソールで hs.reload() を実行してください。"
  fi
}

if [ "${1:-}" = "--uninstall" ]; then
  if [ -L "$DST" ] && [ "$(readlink "$DST")" = "$SRC" ]; then
    rm "$DST"
    echo "remove : $DST"
  fi
  if [ -e "$BAK" ] || [ -L "$BAK" ]; then
    mv "$BAK" "$DST"
    echo "restore: $BAK -> $DST"
  fi
  reload
  exit 0
fi

mkdir -p "$(dirname "$DST")"

if [ -L "$DST" ] && [ "$(readlink "$DST")" = "$SRC" ]; then
  echo "ok     : $DST（インストール済み）"
  reload
  exit 0
fi

# 既存の設定を退避（すでに退避済みなら上書きしない＝最初の状態に必ず戻せる）
if [ -e "$DST" ] || [ -L "$DST" ]; then
  if [ -e "$BAK" ] || [ -L "$BAK" ]; then
    echo "退避先 $BAK が既にあります。先に --uninstall するか手動で確認してください。" >&2
    exit 1
  fi
  mv "$DST" "$BAK"
  echo "backup : $DST -> $BAK"
fi

ln -s "$SRC" "$DST"
echo "link   : $DST -> $SRC"
reload
