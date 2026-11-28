#!/bin/sh
set -eu
CDPATH= cd -P -- "$(dirname -- "$0")"

app_id=com.naughie.nauvim.flutter
entry="$app_id.desktop"
src="share/applications/$entry"
icon_dir=icons/hicolor/256x256/apps
icon="share/$icon_dir/$app_id.png"
binary="$PWD/nauvim"
if [ ! -x "$binary" ] || [ ! -r "$src" ] || [ ! -r "$icon" ]; then
  echo 'Run this script from an extracted Nauvim bundle.' >&2
  exit 1
fi

data_home=${XDG_DATA_HOME:-}
case "$data_home" in
  /*) ;;
  *) data_home="$HOME/.local/share" ;;
esac
applications="$data_home/applications"
mkdir -p -- "$applications"

tmp=$(mktemp -- "$applications/.nauvim.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
while IFS= read -r line; do
  case "$line" in
    Exec=*) printf 'Exec="%s"\n' "$binary" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$src" > "$tmp"
install -D -m 644 -- "$icon" "$data_home/$icon_dir/$app_id.png"
mv -fT -- "$tmp" "$applications/$entry"
printf 'Installed %s\n' "$applications/$entry"
