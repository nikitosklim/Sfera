#!/bin/bash
# собрать-приложение-macos.sh — собирает «Почту Сферы» как отдельное приложение macOS («Почта Сферы.app»).
# Запускать на Mac из любого места:
#   ./инструменты/почта/собрать-приложение-macos.sh            — приложение появится в ~/Applications
#   ./инструменты/почта/собрать-приложение-macos.sh /Applications   — или в другую папку
#
# Нужно (один раз): brew install openssl@3 sdl2 sdl2_ttf, и собранный компилятор Сферы (target/release/запустить).
# После сборки приложение видно в Launchpad и в Spotlight; перетащите его в Dock, если хотите.

set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
DEST="${1:-$HOME/Applications}"

for PKG in sdl2 sdl2_ttf openssl@3; do
    brew list "$PKG" >/dev/null 2>&1 || { echo "Не хватает пакета: brew install $PKG"; exit 1; }
done

if [ -x "$ROOT/target/release/запустить" ]; then
    RUNNER="$ROOT/target/release/запустить"
elif command -v запустить >/dev/null 2>&1; then
    RUNNER=$(command -v запустить)
else
    echo "Не найден компилятор. Соберите его: cargo build --release (в корне проекта)."
    exit 1
fi

export LIBRARY_PATH="$(brew --prefix openssl@3)/lib:$(brew --prefix)/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export CPATH="$(brew --prefix openssl@3)/include:$(brew --prefix)/include${CPATH:+:$CPATH}"

echo "1/3  Собираю «Почту Сферы»…"
(cd инструменты/почта && "$RUNNER" почта_мак.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m --линковать ssl --линковать crypto --линковать objc)

echo "2/3  Собираю приложение…"
APP="$DEST/Почта Сферы.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp инструменты/почта/почта_мак "$APP/Contents/MacOS/Pochta-Sfery"
cp инструменты/иконки/Sfera.icns "$APP/Contents/Resources/Sfera.icns"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Почта Сферы</string>
  <key>CFBundleDisplayName</key><string>Почта Сферы</string>
  <key>CFBundleIdentifier</key><string>ru.sfera.pochta</string>
  <key>CFBundleExecutable</key><string>Pochta-Sfery</string>
  <key>CFBundleIconFile</key><string>Sfera</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "3/3  Подписываю на месте (без неё macOS может ругаться на чужую сборку)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
xattr -cr "$APP" 2>/dev/null || true
touch "$APP"

echo ""
echo "Готово: $APP"
echo "Запуск: двойной щелчок, Launchpad или Spotlight («Почта Сферы»). Перетащите значок в Dock — и она всегда под рукой."
open -R "$APP" 2>/dev/null || true
