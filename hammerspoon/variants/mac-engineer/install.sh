#!/bin/sh
# Macエンジニア向け設定のインストール / アンインストール
#   ./install.sh              既存の ~/.hammerspoon/init.lua を退避し、本設定へのリンクを作成する
#   ./install.sh --uninstall  リンクを削除し、退避した init.lua を復元する
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/init.lua"
DST="$HOME/.hammerspoon/init.lua"
BAK="$HOME/.hammerspoon/init.lua.before-mac-engineer"

reload() {
  # Hammerspoon が起動中かつ hs コマンドが利用可能な場合は、設定を再読み込みする
  if command -v hs >/dev/null 2>&1 && pgrep -q Hammerspoon; then
    hs -c 'hs.reload()' >/dev/null 2>&1 || true
    echo "Hammerspoon の設定を再読み込みした。"
  else
    echo "Hammerspoon コンソールで hs.reload() を実行すること。"
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

# 既存の設定を退避する。退避先が存在する場合は上書きせず中断し、導入前の設定を保護する
if [ -e "$DST" ] || [ -L "$DST" ]; then
  if [ -e "$BAK" ] || [ -L "$BAK" ]; then
    echo "退避先 $BAK が既に存在する。--uninstall を実行するか、内容を確認すること。" >&2
    exit 1
  fi
  mv "$DST" "$BAK"
  echo "backup : $DST -> $BAK"
fi

ln -s "$SRC" "$DST"
echo "link   : $DST -> $SRC"
reload
