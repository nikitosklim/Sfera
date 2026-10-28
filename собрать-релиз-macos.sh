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
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')

for PKG in llvm@18 sdl2 sdl2_ttf; do
    brew list "$PKG" >/dev/null 2>&1 || { echo "Не хватает пакета: brew install $PKG"; exit 1; }
done
export LLVM_SYS_180_PREFIX=$(brew --prefix llvm@18)

echo "1/4  Собираю компилятор..."
cargo build --release

echo "2/4  Собираю панель разработчика..."
(cd инструменты/панель-разработчика && "$ROOT/target/release/запустить" панель_unix.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m)

echo "3/4  Собираю приложение..."
OUT="$ROOT/релиз"
APP="$OUT/Панель Сферы.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib/sfera"
cp инструменты/панель-разработчика/панель_unix "$APP/Contents/MacOS/Sfera-Panel"
for NAME in запустить сфера_lsp сфера_пакеты; do cp "target/release/$NAME" "$APP/Contents/Resources/bin/$NAME"; done
cp examples/привет.код "$APP/Contents/Resources/bin/привет.код"
cp README.md "$APP/Contents/Resources/README.md"
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
chmod +x "$APP/Contents/MacOS/Sfera-Panel" "$APP"/Contents/Resources/bin/запустить "$APP"/Contents/Resources/bin/сфера_lsp "$APP"/Contents/Resources/bin/сфера_пакеты

echo "4/4  Упаковываю..."
(cd "$OUT" && rm -f Sfera-Panel-macOS.zip && ditto -c -k --keepParent "Панель Сферы.app" Sfera-Panel-macOS.zip)
echo "Готово: $OUT/Sfera-Panel-macOS.zip"
