#!/bin/bash
# собрать-apk.sh — собирает Sfera-Panel-Android.apk (панель разработчика
# для Android): SDL2 + SDL2_ttf под ARM64, панель на Сфере (libmain.so),
# маленькая Java-обвязка SDL, подпись. Работает на Linux (так её запускает
# GitHub Actions) и на macOS.
#
# Нужны: Android SDK (build-tools, platforms) и Android NDK, Java (javac,
# keytool), python3, git. Пути берутся из переменных ANDROID_HOME и
# ANDROID_NDK (в GitHub Actions они уже заданы).
#
#   ANDROID_NDK=~/Library/Android/sdk/ndk/27.2.12479018 \
#   ANDROID_HOME=~/Library/Android/sdk  bash ./собрать-apk.sh
#
# Подпись: если задан файл SFERA_KEYSTORE (пароль SFERA_KEYSTORE_PASS,
# псевдоним key), используется он — тогда новые версии устанавливаются
# поверх старых. Иначе создаётся одноразовый ключ: перед установкой новой
# сборки старую версию нужно удалить с телефона.
#
# ⚠️ Это приложение без встроенного компилятора: интерфейс панели, версия,
# описание языка и пример. Запуск программ на самом телефоне — отдельный этап.

set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')
CODE=$(echo "$VERSION" | awk -F. '{ printf "%d", $1*10000 + $2*100 + $3 }')

SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
NDK="${ANDROID_NDK:-$ANDROID_NDK_LATEST_HOME}"
[ -d "$SDK" ] || { echo "Не найден Android SDK: задайте ANDROID_HOME"; exit 1; }
[ -d "$NDK" ] || { echo "Не найден Android NDK: задайте ANDROID_NDK"; exit 1; }
HOST_TAG=linux-x86_64
[ "$(uname -s)" = "Darwin" ] && HOST_TAG=darwin-x86_64
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
SYSROOT="$TOOLCHAIN/sysroot"
BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)
ANDROID_JAR=$(ls -d "$SDK"/platforms/android-*/android.jar | sort -V | tail -1)
echo "NDK: $NDK"
echo "build-tools: $BT"
echo "android.jar: $ANDROID_JAR"

FONT="${SFERA_FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
[ -f "$FONT" ] || { echo "Нет шрифта с кириллицей: $FONT (задайте SFERA_FONT=путь/к/шрифту.ttf)"; exit 1; }

W="$ROOT/релиз/apk-work"
OUT="$ROOT/релиз"
mkdir -p "$W" "$OUT"

if [ ! -x target/release/запустить ]; then
    echo "0/7  Собираю компилятор..."
    cargo build --release
fi

echo "1/7  Загружаю SDL2 и SDL2_ttf..."
[ -d "$W/SDL" ] || git clone --quiet --depth 1 --branch release-2.30.8 https://github.com/libsdl-org/SDL "$W/SDL"
[ -d "$W/SDL_ttf" ] || git clone --quiet --depth 1 --branch release-2.22.0 --recurse-submodules --shallow-submodules https://github.com/libsdl-org/SDL_ttf "$W/SDL_ttf"

echo "2/7  Собираю SDL2 и SDL2_ttf под ARM64 (ndk-build)..."
mkdir -p "$W/jni"
ln -sfn "$W/SDL" "$W/jni/SDL2"
ln -sfn "$W/SDL_ttf" "$W/jni/SDL2_ttf"
echo 'include $(call all-subdir-makefiles)' > "$W/jni/Android.mk"
printf 'APP_ABI := arm64-v8a\nAPP_PLATFORM := android-21\nAPP_STL := c++_shared\n' > "$W/jni/Application.mk"
"$NDK/ndk-build" -C "$W" NDK_PROJECT_PATH="$W" APP_BUILD_SCRIPT="$W/jni/Android.mk" \
    NDK_APPLICATION_MK="$W/jni/Application.mk" NDK_LIBS_OUT="$W/libs" NDK_OUT="$W/obj" -j2
LIBS="$W/libs/arm64-v8a"
ls "$LIBS"

echo "3/7  Компилирую панель на Сфере (libmain.so)..."
rm -rf "$W/src"; mkdir -p "$W/src"
cp инструменты/android/панель_android.код "$W/src/"
(cd "$W/src" && PATH="$TOOLCHAIN/bin:$PATH" SFERA_ANDROID_LIBDIR="$LIBS" \
    "$ROOT/target/release/запустить" панель_android.код --только-собрать \
    --целевая-платформа aarch64-linux-android21 --android-sysroot "$SYSROOT" --android-so \
    --линковать SDL2 --линковать SDL2_ttf)
cp "$W/src/панель_android" "$LIBS/libmain.so"

echo "4/7  Компилирую Java-обвязку SDL..."
rm -rf "$W/classes" "$W/dex"; mkdir -p "$W/classes" "$W/dex"
javac --release 8 -nowarn -cp "$ANDROID_JAR" -d "$W/classes" \
    $(find "$W/SDL/android-project/app/src/main/java" -name '*.java') \
    инструменты/android/apk/PanelActivity.java 2>&1 | grep -v '^Note:\|warning' || true
"$BT/d8" --lib "$ANDROID_JAR" --min-api 21 --output "$W/dex" $(find "$W/classes" -name '*.class')

echo "5/7  Собираю APK..."
"$BT/aapt2" link -o "$W/base.apk" -I "$ANDROID_JAR" --manifest инструменты/android/apk/AndroidManifest.xml \
    --min-sdk-version 21 --target-sdk-version 34 --version-code "$CODE" --version-name "$VERSION"
python3 - "$W" "$LIBS" "$FONT" <<'PY'
import sys, glob, os, zipfile
w, libs, font = sys.argv[1:4]
with zipfile.ZipFile(os.path.join(w, "base.apk"), "a") as z:
    z.write(os.path.join(w, "dex", "classes.dex"), "classes.dex", zipfile.ZIP_DEFLATED)
    for so in sorted(glob.glob(os.path.join(libs, "*.so"))):
        z.write(so, "lib/arm64-v8a/" + os.path.basename(so), zipfile.ZIP_STORED)
    z.write(font, "assets/font.ttf", zipfile.ZIP_DEFLATED)
PY

echo "6/7  Выравниваю и подписываю..."
"$BT/zipalign" -f -p 4 "$W/base.apk" "$W/aligned.apk"
if [ -n "$SFERA_KEYSTORE" ]; then
    KS="$SFERA_KEYSTORE"; KP="${SFERA_KEYSTORE_PASS:-android}"
else
    KS="$W/debug.keystore"; KP=android
    [ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
        -alias key -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Sfera"
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KP" --key-pass "pass:$KP" --out "$OUT/Sfera-Panel-Android.apk" "$W/aligned.apk"
"$BT/apksigner" verify "$OUT/Sfera-Panel-Android.apk"

echo "7/7  Готово: $OUT/Sfera-Panel-Android.apk"
