#!/bin/bash
# собрать-deb.sh ПАПКА_ЛИНУКС_СБОРКИ ВЫХОДНАЯ_ПАПКА ВЕРСИЯ — делает установочный пакет
# Sfera-Setup-Linux-<версия>.deb из готовой папки Sfera-Panel-Linux (её собирает собрать-релиз-linux.sh).
# Ставит программу в /opt/sfera-panel, команду «sfera-panel» в /usr/bin, пункт «Панель Сферы» с иконкой
# в меню приложений. Установка:  sudo apt install ./Sfera-Setup-Linux-<версия>.deb  (подтянет зависимости).
set -e
SRC=$(cd "$1" && pwd); OUT=$(cd "$2" && pwd); VERSION="$3"
[ -n "$VERSION" ] || { echo "Не указана версия"; exit 1; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ARCH=$(dpkg --print-architecture)
PKG="$OUT/deb-сборка"
rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/sfera-panel" "$PKG/usr/bin" "$PKG/usr/share/applications"

cp -a "$SRC/." "$PKG/opt/sfera-panel/"
# Ярлык и значки ставит сам пакет, скрипт для ручной установки ярлыка не нужен.
rm -rf "$PKG/opt/sfera-panel/Установить-ярлык.sh" "$PKG/opt/sfera-panel/icons"

for N in 16 24 32 48 64 128 256 512; do
    mkdir -p "$PKG/usr/share/icons/hicolor/${N}x${N}/apps"
    cp "$ROOT/инструменты/иконки/linux/${N}x${N}.png" "$PKG/usr/share/icons/hicolor/${N}x${N}/apps/sfera-panel.png"
done

cat > "$PKG/usr/bin/sfera-panel" <<'LAUNCH'
#!/bin/sh
cd /opt/sfera-panel && exec ./Sfera-Panel "$@"
LAUNCH

cat > "$PKG/usr/share/applications/sfera-panel.desktop" <<'ENTRY'
[Desktop Entry]
Type=Application
Name=Панель Сферы
Comment=Установка и обновление языка Сфера
Exec=sfera-panel
Icon=sfera-panel
Terminal=false
Categories=Development;
StartupWMClass=Sfera-Panel
ENTRY

SIZE=$(du -sk "$PKG" | cut -f1)
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: sfera-panel
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: libsdl2-2.0-0, libsdl2-ttf-2.0-0, clang, llvm-18
Maintainer: Sfera Project <noreply@users.noreply.github.com>
Homepage: https://языксфера.рф
Description: Панель Сферы — установка и обновление языка программирования Сфера
 Оконная панель разработчика с компилятором Сферы, стандартной библиотекой и пакетным менеджером.
 После установки запустите «Панель Сферы» из меню приложений и нажмите «Установить Сферу».
CONTROL

chmod 755 "$PKG/usr/bin/sfera-panel" "$PKG/opt/sfera-panel/Sfera-Panel" "$PKG/opt/sfera-panel/Sfera-Panel.sh"
find "$PKG" -type d -exec chmod 755 {} +
DEB="$OUT/Sfera-Setup-Linux-$VERSION.deb"
rm -f "$DEB"
dpkg-deb --build --root-owner-group "$PKG" "$DEB" >/dev/null
rm -rf "$PKG"
echo "Готово: $DEB ($(du -h "$DEB" | cut -f1))"
