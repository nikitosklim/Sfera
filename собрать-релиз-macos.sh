#!/bin/bash
# собрать-релиз-macos.sh — собирает «Панель Сферы.app» и архив
# Sfera-Panel-macOS.zip: панель разработчика + компилятор + стандартная
# библиотека. Запускать из корня репозитория на Mac:
#   ./собрать-релиз-macos.sh
#
# Нужны (один раз):  brew install llvm@18 sdl2 sdl2_ttf   и   Rust (rustup).
# Сборка идёт под архитектуру вашего Mac (Intel или Apple Silicon).
#
# Приложение не подписано: при первом запуске нажмите правой кнопкой →
# «Открыть», либо выполните:  xattr -dr com.apple.quarantine "/Applications/Панель Сферы.app"
# Копировать приложение нужно именно в /Applications: оттуда панель берёт
# компилятор при нажатии «Установить Сферу».

set -e
# Минимальная версия macOS: без этого бинарники берут версию раннера (macOS 15), и на более
# старых системах значок приложения перечёркнут.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')

for PKG in llvm@18 sdl2 sdl2_ttf; do
    brew list "$PKG" >/dev/null 2>&1 || { echo "Не хватает пакета: brew install $PKG"; exit 1; }
done
export LLVM_SYS_180_PREFIX=$(brew --prefix llvm@18)

PANEL_VERSION=$(grep -A1 'функция текущая_версия' инструменты/панель-разработчика/панель_unix.код | grep -o '"[^"]*"' | head -1 | tr -d '"')
[ -n "$PANEL_VERSION" ] || PANEL_VERSION="$VERSION"

echo "1/5  Собираю компилятор..."
cargo build --release

echo "2/5  Собираю панель разработчика..."
(cd инструменты/панель-разработчика && "$ROOT/target/release/запустить" панель_unix.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m)

echo "3/5  Собираю приложение..."
OUT="$ROOT/релиз"
APP="$OUT/Панель Сферы.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib/sfera"
cp инструменты/панель-разработчика/панель_unix "$APP/Contents/MacOS/Sfera-Panel"
for NAME in запустить сфера_lsp сфера_пакеты сфера; do cp "target/release/$NAME" "$APP/Contents/Resources/bin/$NAME"; done
cp examples/привет.код "$APP/Contents/Resources/bin/привет.код"
cp README.md "$APP/Contents/Resources/README.md"
cp инструменты/иконки/Sfera.icns "$APP/Contents/Resources/Sfera.icns"
cp -r стандартная_библиотека "$APP/Contents/Resources/lib/sfera/стандартная_библиотека"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Панель Сферы</string>
  <key>CFBundleDisplayName</key><string>Панель Сферы</string>
  <key>CFBundleIdentifier</key><string>ru.sfera.panel</string>
  <key>CFBundleExecutable</key><string>Sfera-Panel</string>
  <key>CFBundleIconFile</key><string>Sfera</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
chmod +x "$APP/Contents/MacOS/Sfera-Panel" "$APP"/Contents/Resources/bin/запустить "$APP"/Contents/Resources/bin/сфера_lsp "$APP"/Contents/Resources/bin/сфера_пакеты "$APP"/Contents/Resources/bin/сфера

# Подпись «ad hoc»: не заменяет подпись разработчика, но без неё на Apple Silicon приложение не запускается совсем.
codesign --force --deep -s - "$APP" || echo "Предупреждение: codesign не сработал"

echo "4/5  Упаковываю архив..."
(cd "$OUT" && rm -f Sfera-Panel-macOS.zip && ditto -c -k --keepParent "Панель Сферы.app" Sfera-Panel-macOS.zip)
echo "Готово: $OUT/Sfera-Panel-macOS.zip"

# Установочный образ: открываешь .dmg и перетаскиваешь «Панель Сферы» в «Программы».
echo "5/5  Собираю установочный образ (.dmg)..."
case "$(uname -m)" in arm64) ARCH_LABEL=ARM ;; *) ARCH_LABEL=Intel ;; esac
DMG="$OUT/Sfera-Setup-macOS-$ARCH_LABEL-$PANEL_VERSION.dmg"
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Панель Сферы.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Панель Сферы" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
