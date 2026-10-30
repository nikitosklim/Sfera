#!/bin/bash
# собрать-android-компилятор.sh — собирает компилятор «Сферы» и линковщик
# ld.lld под Android ARM64 (aarch64-linux-android) на Linux-машине
# (так её запускает GitHub Actions).
#
#   bash ./собрать-android-компилятор.sh llvm      — LLVM 18 + lld + libffi под Android
#                                                     (долго: 1–2 часа, результат кэшируется)
#   bash ./собрать-android-компилятор.sh compiler  — сам компилятор + «мост» llvm-config
#   bash ./собрать-android-компилятор.sh           — оба шага подряд
#
# Результат: релиз/android-bin/{запустить,ld.lld}. Нужны: Android NDK
# (ANDROID_NDK или ANDROID_NDK_LATEST_HOME), cmake, ninja, git, curl,
# пакет llvm-18-dev (host llvm-tblgen и llvm-config), rustup.

set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
NDK="${ANDROID_NDK:-$ANDROID_NDK_LATEST_HOME}"
[ -d "$NDK" ] || { echo "Не найден Android NDK: задайте ANDROID_NDK"; exit 1; }
HOST_LLVM="${HOST_LLVM:-/usr/lib/llvm-18}"
NDK_BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=23
W="$ROOT/релиз/android-llvm"
INSTALL="$W/install"
BRIDGE="$W/bridge"
OUT="$ROOT/релиз/android-bin"
JOBS=$(nproc)
STEP="${1:-all}"

build_llvm() {
    if [ -f "$INSTALL/lib/libLLVMCore.a" ] && [ -f "$INSTALL/lib/libffi.a" ] && [ -x "$INSTALL/bin/lld" ]; then
        echo "LLVM под Android уже собран (кэш) — пропускаю."
        return
    fi
    mkdir -p "$W"
    echo "1/3  Загружаю LLVM 18.1.3 (та же версия, что у host llvm-tblgen)..."
    [ -d "$W/llvm-project" ] || git clone --quiet --depth 1 --branch llvmorg-18.1.3 https://github.com/llvm/llvm-project "$W/llvm-project"

    echo "2/3  Собираю LLVM + lld под Android (долго)..."
    mkdir -p "$W/build"
    cmake -G Ninja -S "$W/llvm-project/llvm" -B "$W/build" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_static \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL" \
        -DLLVM_NATIVE_TOOL_DIR="$HOST_LLVM/bin" \
        -DANDROID_ALLOW_UNDEFINED_SYMBOLS=ON -DLLVM_ENABLE_PLUGINS=OFF \
        -DLLVM_ENABLE_PROJECTS=lld \
        -DLLVM_TARGETS_TO_BUILD=AArch64 \
        -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
        -DBUILD_SHARED_LIBS=OFF
    ninja -C "$W/build" -j"$JOBS" install
    rm -rf "$W/build"

    echo "3/3  Собираю libffi под Android..."
    FFI=3.4.6
    [ -d "$W/libffi-$FFI" ] || { curl -fsSL -o "$W/libffi.tar.gz" "https://github.com/libffi/libffi/releases/download/v$FFI/libffi-$FFI.tar.gz"; tar -xzf "$W/libffi.tar.gz" -C "$W"; }
    mkdir -p "$W/ffi-build" && cd "$W/ffi-build"
    CC="$NDK_BIN/aarch64-linux-android$API-clang" AR="$NDK_BIN/llvm-ar" RANLIB="$NDK_BIN/llvm-ranlib" \
        "$W/libffi-$FFI/configure" --host=aarch64-linux-android --prefix="$W/ffi-install" --enable-static --disable-shared
    make -j"$JOBS" && make install
    cp "$W/ffi-install/lib/libffi.a" "$INSTALL/lib/libffi.a"
    cd "$ROOT"
    rm -rf "$W/llvm-project" "$W/ffi-build" "$W/libffi-$FFI" "$W/libffi.tar.gz"
    echo "LLVM под Android готов: $INSTALL"
}

build_compiler() {
    [ -f "$INSTALL/lib/libLLVMCore.a" ] || { echo "Сначала: bash $0 llvm"; exit 1; }
    mkdir -p "$BRIDGE/bin" "$OUT"
    # «Мост» llvm-config: llvm-sys запускает llvm-config на хосте, а настоящий
    # (собранный под Android) на Linux не запустится. Версии и флаги берём у
    # host llvm-config, а библиотеки подменяем на Android-версии.
    cat > "$BRIDGE/bin/llvm-config" <<BR
#!/bin/bash
HOST="$HOST_LLVM/bin/llvm-config"
INST="$INSTALL"
case "\$1" in
    --libdir) echo "\$INST/lib" ;;
    --includedir) echo "\$INST/include" ;;
    --libs) ls "\$INST"/lib/libLLVM*.a | xargs -n1 basename | sed -e 's/^lib/-l/' -e 's/\.a\$//' | tr '\n' ' '; echo ;;
    --libnames|--link-static) ls "\$INST"/lib/libLLVM*.a | xargs -n1 basename ;;
    --system-libs) echo "-lc++_static -lc++abi -lm" ;;
    *) "\$HOST" "\$@" | sed -e 's/-lffi//g' -e 's/-lzstd//g' -e 's/-lz //g' -e 's/-lz\$//g' -e 's/-lxml2//g' -e 's/-ledit//g' ;;
esac
BR
    chmod +x "$BRIDGE/bin/llvm-config"
    # LLVM_SYS_180_PREFIX указывает на папку, где лежит bin/llvm-config
    BUILTINS=$(find "$NDK" -name "libclang_rt.builtins-aarch64-android.a" | head -1)
    [ -n "$BUILTINS" ] || { echo "Не найден libclang_rt.builtins-aarch64-android.a в NDK"; exit 1; }
    rustup target add aarch64-linux-android
    export LLVM_SYS_180_PREFIX="$BRIDGE"
    export CC_aarch64_linux_android="$NDK_BIN/aarch64-linux-android$API-clang"
    export CXX_aarch64_linux_android="$NDK_BIN/aarch64-linux-android$API-clang++"
    export AR_aarch64_linux_android="$NDK_BIN/llvm-ar"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_BIN/aarch64-linux-android$API-clang"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=$BUILTINS"
    export PATH="$NDK_BIN:$PATH"
    echo "Собираю компилятор под aarch64-linux-android..."
    cargo build --release --target aarch64-linux-android --bin запустить
    cp "target/aarch64-linux-android/release/запустить" "$OUT/запустить"
    cp "$INSTALL/bin/lld" "$OUT/lld"
    "$NDK_BIN/llvm-strip" "$OUT/запустить" "$OUT/lld" || true
    file "$OUT/запустить" "$OUT/lld"
    ls -la "$OUT"
}

case "$STEP" in
    llvm) build_llvm ;;
    compiler) build_compiler ;;
    all) build_llvm; build_compiler ;;
    *) echo "Использование: $0 [llvm|compiler]"; exit 1 ;;
esac
