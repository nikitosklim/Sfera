#!/bin/bash
# собрать-android-упаковщик.sh — собирает сфера_apk (упаковщик APK) под Android ARM64:
# его вызывает кнопка «APK» в панели на телефоне. Запускать ПОСЛЕ
# `собрать-android-компилятор.sh compiler`: используются те же зависимости и «мост» llvm-config
# (cargo собирает зависимости пакета целиком, поэтому нужен тот же LLVM_SYS_180_PREFIX).
# Результат: релиз/android-bin/сфера_apk
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
NDK="${ANDROID_NDK:-$ANDROID_NDK_LATEST_HOME}"
[ -d "$NDK" ] || { echo "Не найден Android NDK: задайте ANDROID_NDK"; exit 1; }
NDK_BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=23
BRIDGE="$ROOT/релиз/android-llvm/bridge"
OUT="$ROOT/релиз/android-bin"
[ -x "$BRIDGE/bin/llvm-config" ] || { echo "Нет $BRIDGE/bin/llvm-config — сначала: bash ./собрать-android-компилятор.sh compiler"; exit 1; }
BUILTINS=$(find "$NDK" -name "libclang_rt.builtins-aarch64-android.a" | head -1)
export LLVM_SYS_180_PREFIX="$BRIDGE"
export CC_aarch64_linux_android="$NDK_BIN/aarch64-linux-android$API-clang"
export CXX_aarch64_linux_android="$NDK_BIN/aarch64-linux-android$API-clang++"
export AR_aarch64_linux_android="$NDK_BIN/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_BIN/aarch64-linux-android$API-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=$BUILTINS"
export PATH="$NDK_BIN:$PATH"
rustup target add aarch64-linux-android
cargo build --release --target aarch64-linux-android --bin сфера_apk
mkdir -p "$OUT"
cp "target/aarch64-linux-android/release/сфера_apk" "$OUT/сфера_apk"
"$NDK_BIN/llvm-strip" "$OUT/сфера_apk" || true
ls -la "$OUT"
