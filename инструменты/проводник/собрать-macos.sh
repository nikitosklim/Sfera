#!/bin/bash
# собрать-macos.sh — делает из Проводника обычное приложение macOS:
# «Проводник Сферы.app» с иконкой. Его можно положить в «Программы»,
# найти в Launchpad и запускать одним нажатием.
#
# Запуск из корня репозитория:
#   ./инструменты/проводник/собрать-macos.sh
#   ./инструменты/проводник/собрать-macos.sh --с-библиотеками   (SDL2 внутри приложения)
#
# Нужно один раз:  brew install sdl2 sdl2_ttf
# Компилятор берётся из target/release/запустить, из PATH или из «Панель Сферы.app».
# Приложение не подписано разработчиком: при первом запуске — правая кнопка → «Открыть»,
# либо:  xattr -dr "com.apple.quarantine" "/Applications/Проводник Сферы.app"

set -e
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
BUNDLE=0
[ "$1" = "--с-библиотеками" ] && BUNDLE=1

for PKG in sdl2 sdl2_ttf; do
    brew list "$PKG" >/dev/null 2>&1 || { echo "Не хватает пакета: brew install $PKG"; exit 1; }
done

# Где компилятор
if [ -x "$ROOT/target/release/запустить" ]; then COMPILER="$ROOT/target/release/запустить"
elif command -v запустить >/dev/null 2>&1; then COMPILER=$(command -v запустить)
elif [ -x "/Applications/Панель Сферы.app/Contents/Resources/bin/запустить" ]; then COMPILER="/Applications/Панель Сферы.app/Contents/Resources/bin/запустить"
else echo "Компилятор не найден. Соберите его (cargo build --release) или установите «Панель Сферы»."; exit 1; fi
echo "Компилятор: $COMPILER"

echo "1/4  Собираю Проводник..."
(cd инструменты/проводник && "$COMPILER" проводник.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m)
[ -x инструменты/проводник/проводник ] || { echo "Сборка не создала файл проводник"; exit 1; }

echo "2/4  Собираю приложение..."
OUT="$ROOT/релиз"
APP="$OUT/Проводник Сферы.app"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp инструменты/проводник/проводник "$APP/Contents/MacOS/Sfera-Explorer"
cp инструменты/иконки/Sfera.icns "$APP/Contents/Resources/Sfera.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Проводник Сферы</string>
  <key>CFBundleDisplayName</key><string>Проводник Сферы</string>
  <key>CFBundleIdentifier</key><string>ru.sfera.provodnik</string>
  <key>CFBundleExecutable</key><string>Sfera-Explorer</string>
  <key>CFBundleIconFile</key><string>Sfera</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
chmod +x "$APP/Contents/MacOS/Sfera-Explorer"

if [ "$BUNDLE" = 1 ]; then
    echo "3/4  Встраиваю библиотеки SDL2..."
    FW="$APP/Contents/Frameworks"; mkdir -p "$FW"
    # рекурсивно копируем всё, что бинарник берёт из Homebrew, и переписываем пути
    bundle_libs() {
        local FILE="$1" DEP
        for DEP in $(otool -L "$FILE" | tail -n +2 | awk '{print $1}' | grep -E '^(/opt/homebrew|/usr/local)'); do
            local NAME=$(basename "$DEP")
            if [ ! -f "$FW/$NAME" ]; then
                cp -L "$DEP" "$FW/$NAME"; chmod u+w "$FW/$NAME"
                install_name_tool -id "@rpath/$NAME" "$FW/$NAME"
                bundle_libs "$FW/$NAME"
            fi
            install_name_tool -change "$DEP" "@rpath/$NAME" "$FILE"
        done
    }
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Sfera-Explorer" 2>/dev/null || true
    bundle_libs "$APP/Contents/MacOS/Sfera-Explorer"
else
    echo "3/4  Библиотеки SDL2 берутся из Homebrew (--с-библиотеками встроит их в приложение)."
fi

echo "4/4  Подписываю (ad hoc)..."
codesign --force --deep -s - "$APP" || echo "Предупреждение: codesign не сработал"
(cd "$OUT" && rm -f Sfera-Explorer-macOS.zip && ditto -c -k --keepParent "Проводник Сферы.app" Sfera-Explorer-macOS.zip)
echo
echo "Готово: $APP"
echo "Архив:  $OUT/Sfera-Explorer-macOS.zip"
echo "Скопируйте приложение в «Программы»:  cp -R \"$APP\" /Applications/"
