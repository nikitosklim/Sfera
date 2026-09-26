#!/bin/bash
# собрать-android.sh — кросс-компиляция компилятора "Сфера" под Android
# (aarch64-linux-android), чтобы его затем можно было зашить прямо в APK
# и запускать на устройстве (см. подтверждённый, рабочий механизм в
# ИСТОРИЯ_РАЗРАБОТКИ.md — "Android-приложение может запускать собственные
# бинарники, зашитые в APK").
#
# ⚠️ ЧЕСТНО, ПРОЧИТАЙ ПЕРЕД ЗАПУСКОМ:
#
# 1. Официальная документация самого llvm-sys (крейта, через который наш
#    компилятор говорит с LLVM) прямо пишет про кросс-компиляцию:
#    "Will theoretically work, but hasn't been tested" — теоретически
#    должна работать, но сами разработчики никогда её не проверяли. Это
#    не типовой, хорошо протоптанный путь.
#
# 2. Этот скрипт НЕ ПРОВЕРЕН ВЖИВУЮ (у меня физически нет macOS-машины с
#    ресурсами для этого — см. честно измеренные ограничения песочницы в
#    ИСТОРИЯ_РАЗРАБОТКИ.md: 6.4GB диска, 3.9GB RAM). Написан максимально
#    аккуратно, по официально задокументированному подходу LLVM для
#    кросс-компиляции (LLVM_TABLEGEN, NDK toolchain file), но первая
#    реальная проверка — твоя, как и с Windows-установщиком раньше.
#
# 3. Время и место: сборка LLVM занимает от 30 минут до нескольких часов
#    в зависимости от машины, и требует ~15-25GB свободного диска для
#    исходников + сборочных файлов (даже с LLVM_TARGETS_TO_BUILD,
#    ограниченным только AArch64, для экономии времени).
#
# 4. Homebrew больше не распространяет android-ndk/android-sdk
#    напрямую (PKGы сняты с поддержки в 2024) — NDK ставится через
#    официальный sdkmanager (command-line tools), см. Этап 2.
#
# Использование:
#   chmod +x собрать-android.sh
#   ./собрать-android.sh

set -e  # остановиться при первой же ошибке, не продолжать вслепую

PROJECT_ROOT=$(cd "$(dirname "$0")" && pwd)
WORK_DIR="$PROJECT_ROOT/android-сборка"
mkdir -p "$WORK_DIR"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Кросс-компиляция компилятора «Сфера» под Android"
echo "  Рабочая папка: $WORK_DIR"
echo "════════════════════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------
# Этап 1: проверка предпосылок
# ---------------------------------------------------------------------
echo "── Этап 1/10: проверка предпосылок ──"

if ! command -v brew &> /dev/null; then
    echo "ОШИБКА: Homebrew не найден. Установи его сначала: https://brew.sh"
    exit 1
fi

for PKG in cmake ninja git; do
    if ! brew list "$PKG" &> /dev/null; then
        echo "Устанавливаю $PKG через Homebrew..."
        brew install "$PKG"
    fi
done

if ! command -v rustup &> /dev/null; then
    echo "ОШИБКА: rustup не найден. Установи Rust сначала: https://rustup.rs"
    exit 1
fi

# Нужен host-собранный llvm-tblgen (для генерации кода во время сборки —
# запускается на хосте даже при кросс-компиляции конечных библиотек, см.
# честное объяснение LLVM_TABLEGEN ниже) — переиспользуем уже
# установленный Homebrew llvm@18 (тот же, что уже нужен для сборки самого
# компилятора под macOS, согласно README.md/ИСТОРИЯ_РАЗРАБОТКИ.md).
if ! brew list llvm@18 &> /dev/null; then
    echo "Устанавливаю llvm@18 через Homebrew (нужен host llvm-tblgen)..."
    brew install llvm@18
fi
LLVM_HOST_PREFIX=$(brew --prefix llvm@18)
LLVM_TBLGEN_HOST="$LLVM_HOST_PREFIX/bin/llvm-tblgen"
if [ ! -x "$LLVM_TBLGEN_HOST" ]; then
    echo "ОШИБКА: не нашёл $LLVM_TBLGEN_HOST — переустанови llvm@18 (brew reinstall llvm@18)."
    exit 1
fi
echo "✓ Предпосылки на месте (host llvm-tblgen: $LLVM_TBLGEN_HOST)"
echo ""

# ---------------------------------------------------------------------
# Этап 2: Rust-таргет для Android
# ---------------------------------------------------------------------
echo "── Этап 2/10: rustup target add aarch64-linux-android ──"
rustup target add aarch64-linux-android
echo "✓ Готово"
echo ""

# ---------------------------------------------------------------------
# Этап 3: установка Android NDK.
#
# ⚠️ ИСПРАВЛЕНО ПО ХОДУ, НАЙДЕНО РЕАЛЬНОЙ ПРОВЕРКОЙ: первая версия этого
# скрипта пыталась вручную скачать command-line tools через curl+grep по
# странице developer.android.com — номер сборки в ссылке у Google
# периодически меняется, и это оказалось хрупко (реально подвело на
# первом же запуске). Homebrew всё-таки поставляет замену для снятых с
# поддержки android-ndk/android-sdk — она просто называется иначе:
# "android-commandlinetools" (cask). Он сам следит за актуальностью
# ссылок — надёжнее самодельной загрузки.
# ---------------------------------------------------------------------
echo "── Этап 3/10: Android NDK ──"

if ! brew list --cask android-commandlinetools &> /dev/null; then
    echo "Устанавливаю Android command-line tools через Homebrew..."
    brew install --cask android-commandlinetools
fi

ANDROID_SDK_ROOT=$(brew --prefix)/share/android-commandlinetools
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
    echo "ОШИБКА: не нашёл sdkmanager по пути $SDKMANAGER"
    echo "Проверь, куда реально установился cask: brew --prefix android-commandlinetools"
    echo "(на некоторых конфигурациях путь может отличаться от ожидаемого выше)."
    exit 1
fi

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home 2>/dev/null || echo '')}"
if [ -z "$JAVA_HOME" ]; then
    echo "ОШИБКА: sdkmanager требует Java (JDK). Установи: brew install openjdk"
    exit 1
fi

if [ ! -d "$ANDROID_SDK_ROOT/ndk" ] || [ -z "$(ls -A "$ANDROID_SDK_ROOT/ndk" 2>/dev/null)" ]; then
    echo "Устанавливаю NDK через sdkmanager (согласись с лицензией, если спросит)..."
    yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses > /dev/null 2>&1 || true
    "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" "ndk;27.2.12479018"
fi

NDK_PATH=$(find "$ANDROID_SDK_ROOT/ndk" -maxdepth 1 -mindepth 1 -type d | head -1)
if [ -z "$NDK_PATH" ]; then
    echo "ОШИБКА: NDK не установился. Проверь вывод sdkmanager выше."
    exit 1
fi
NDK_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
if [ ! -f "$NDK_TOOLCHAIN_FILE" ]; then
    echo "ОШИБКА: не нашёл $NDK_TOOLCHAIN_FILE — NDK установлен некорректно."
    exit 1
fi
echo "✓ NDK готов: $NDK_PATH"
echo ""

# ---------------------------------------------------------------------
# Этап 4: исходники LLVM 18.1.8 (та же версия, что и для macOS-сборки —
# см. README.md, Cargo.toml: inkwell requires llvm18-0).
# ---------------------------------------------------------------------
echo "── Этап 4/10: исходники LLVM 18.1.8 ──"
LLVM_SRC="$WORK_DIR/llvm-project"
if [ ! -d "$LLVM_SRC" ]; then
    echo "Клонирую llvm-project (тег llvmorg-18.1.8, shallow — это всё равно займёт время)..."
    git clone --depth 1 --branch llvmorg-18.1.8 https://github.com/llvm/llvm-project.git "$LLVM_SRC"
fi
echo "✓ Исходники на месте"
echo ""

# ---------------------------------------------------------------------
# Этап 5: кросс-компиляция LLVM под aarch64-linux-android23.
#
# ⚠️ САМЫЙ ДОЛГИЙ И САМЫЙ РИСКОВАННЫЙ ШАГ. LLVM_TABLEGEN указывает на
# УЖЕ СОБРАННЫЙ host-инструмент (Homebrew llvm@18) — официально
# задокументированный LLVM способ избежать попытки собрать/запустить
# tblgen для Android (см. https://llvm.org/docs/CMake.html —
# "LLVM_TABLEGEN ... intended for cross-compiling").
#
# LLVM_TARGETS_TO_BUILD ограничен ТОЛЬКО AArch64 — компилятор,
# работающий НА Android, генерирующий код ДЛЯ Android (та же
# архитектура) — этого достаточно для первой, рабочей версии. Если
# позже понадобится, чтобы Android-версия компилятора умела собирать
# программы и под другие архитектуры — список можно расширить (ценой
# кратно большего времени сборки).
# ---------------------------------------------------------------------
echo "── Этап 5/10: сборка LLVM для Android (самый долгий шаг — от 30 минут до нескольких часов) ──"
LLVM_ANDROID_BUILD="$WORK_DIR/llvm-android-build"
LLVM_ANDROID_INSTALL="$WORK_DIR/llvm-android-install"

if [ ! -f "$LLVM_ANDROID_INSTALL/lib/libLLVMCore.a" ]; then
    mkdir -p "$LLVM_ANDROID_BUILD"
    cd "$LLVM_ANDROID_BUILD"
    cmake -G Ninja "$LLVM_SRC/llvm" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_TOOLCHAIN_FILE" \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM=android-23 \
        -DANDROID_ALLOW_UNDEFINED_SYMBOLS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$LLVM_ANDROID_INSTALL" \
        -DLLVM_TABLEGEN="$LLVM_TBLGEN_HOST" \
        -DLLVM_TARGETS_TO_BUILD="AArch64" \
        -DLLVM_BUILD_TOOLS=ON \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DBUILD_SHARED_LIBS=OFF
    ninja install
    cd "$PROJECT_ROOT"
else
    echo "Уже собрано (найден $LLVM_ANDROID_INSTALL/lib/libLLVMCore.a) — пропускаю."
fi
echo "✓ LLVM для Android собран: $LLVM_ANDROID_INSTALL"
echo ""

# ---------------------------------------------------------------------
# Этап 6: сборка libffi для Android.
#
# ⚠️ ЧЕСТНО НАЙДЕНО РЕАЛЬНОЙ ПРОВЕРКОЙ (после нескольких неверных
# гипотез, см. ИСТОРИЯ_РАЗРАБОТКИ.md за полными подробностями): "-lffi"
# в ошибке линковки — НЕ лишний, ошибочно протёкший флаг, а настоящая,
# нужная зависимость. LLVM собирает свой интерпретатор (часть,
# используемая внутри самого LLVM для служебных целей) со ссылками на
# символы libffi независимо от LLVM_ENABLE_FFI — сама библиотека
# LLVMInterpreter реально ссылается на ffi_call/ffi_prep_cif и другие.
# Убирать "-lffi" из линковки (например, отключив это в inkwell) ломает
# сборку — было проверено напрямую и отменено, когда это сломало уже
# рабочую сборку под host. Правильное решение — собрать настоящую
# libffi.a для aarch64-android и положить её туда, куда уже смотрит
# линковщик — никакой правки LLVM или моста для этого не требуется.
# ---------------------------------------------------------------------
echo "── Этап 6/10: сборка libffi для Android ──"
NDK_CLANG_BIN="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin"
if [ ! -d "$NDK_CLANG_BIN" ]; then
    NDK_CLANG_BIN="$NDK_PATH/toolchains/llvm/prebuilt/darwin-arm64/bin"
fi
if [ ! -d "$NDK_CLANG_BIN" ]; then
    echo "ОШИБКА: не нашёл NDK-toolchain bin — проверь $NDK_PATH/toolchains/llvm/prebuilt/"
    exit 1
fi

FFI_VERSION="3.4.6"
FFI_SRC_DIR="$WORK_DIR/libffi-$FFI_VERSION"

if [ ! -f "$LLVM_ANDROID_INSTALL/lib/libffi.a" ]; then
    if [ ! -d "$FFI_SRC_DIR" ]; then
        echo "Скачиваю исходники libffi $FFI_VERSION..."
        curl -fsSL -o "$WORK_DIR/libffi.tar.gz" \
            "https://github.com/libffi/libffi/releases/download/v${FFI_VERSION}/libffi-${FFI_VERSION}.tar.gz"
        tar -xzf "$WORK_DIR/libffi.tar.gz" -C "$WORK_DIR"
        rm -f "$WORK_DIR/libffi.tar.gz"
    fi

    FFI_BUILD_DIR="$WORK_DIR/libffi-android-build"
    mkdir -p "$FFI_BUILD_DIR"
    cd "$FFI_BUILD_DIR"

    export CC="$NDK_CLANG_BIN/aarch64-linux-android23-clang"
    export CXX="$NDK_CLANG_BIN/aarch64-linux-android23-clang++"
    export AR="$NDK_CLANG_BIN/llvm-ar"
    export RANLIB="$NDK_CLANG_BIN/llvm-ranlib"

    # --enable-static --disable-shared: нам нужен только .a файл для
    # статической линковки — та же схема, что и вся остальная сборка
    # (LLVM тоже статические .a, не .so).
    "$FFI_SRC_DIR/configure" \
        --host=aarch64-linux-android \
        --prefix="$WORK_DIR/libffi-android-install" \
        --enable-static \
        --disable-shared
    make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
    make install

    unset CC CXX AR RANLIB
    cd "$PROJECT_ROOT"

    cp "$WORK_DIR/libffi-android-install/lib/libffi.a" "$LLVM_ANDROID_INSTALL/lib/libffi.a"
else
    echo "Уже собрано (найден $LLVM_ANDROID_INSTALL/lib/libffi.a) — пропускаю."
fi
echo "✓ libffi для Android собран: $LLVM_ANDROID_INSTALL/lib/libffi.a"
echo ""

# ---------------------------------------------------------------------
# Этап 7: "мост" llvm-config для llvm-sys.
#
# ⚠️ ЧЕСТНО, САМАЯ НЕОБЫЧНАЯ ЧАСТЬ ЭТОГО СКРИПТА: llvm-sys ищет
# ИСПОЛНЯЕМЫЙ, ЗАПУСКАЕМЫЙ НА ХОСТЕ llvm-config, который описывает
# флаги компиляции/линковки. При кросс-компиляции CMake собрал бы
# llvm-config КАК ANDROID-бинарник (не запускается на macOS) — это и
# есть корень того самого "hasn't been tested" сценария. Обходим:
# наш собственный, host-исполняемый скрипт-обёртка, который берёт
# большинство ответов у РЕАЛЬНОГО host llvm-config (та же версия,
# 18.1.8, у Homebrew llvm@18 — флаги компиляции/версии совпадают
# между host и Android сборками), но подменяет пути к библиотекам и
# линковочные флаги на Android-собранные .a файлы.
# ---------------------------------------------------------------------
echo "── Этап 7/10: llvm-config мост для llvm-sys ──"
BRIDGE_DIR="$WORK_DIR/llvm-config-android-bridge/bin"
mkdir -p "$BRIDGE_DIR"
cat > "$BRIDGE_DIR/llvm-config" << BRIDGE_EOF
#!/bin/bash
# Автоматически сгенерировано собрать-android.sh — НЕ настоящий
# llvm-config, а host-исполняемая "обёртка", отвечающая флагами для
# Android-собранных статических библиотек LLVM (см. честное объяснение
# в комментарии перед Этапом 6 в собрать-android.sh).
LLVM_HOST_CONFIG="$LLVM_HOST_PREFIX/bin/llvm-config"
ANDROID_INSTALL="$LLVM_ANDROID_INSTALL"

case "\$1" in
    --libdir)
        echo "\$ANDROID_INSTALL/lib"
        ;;
    --includedir)
        echo "\$ANDROID_INSTALL/include"
        ;;
    --libs|--libnames|--link-static)
        # Статическая линковка всех .a файлов из Android-сборки —
        # проще и надёжнее, чем пытаться воспроизвести host llvm-config
        # точный список компонентов для целевого aarch64-only билда.
        ls "\$ANDROID_INSTALL"/lib/libLLVM*.a 2>/dev/null | xargs -n1 basename
        ;;
    --system-libs)
        echo "-lc++ -lm"
        ;;
    *)
        # Версия, --cxxflags, --has-rtti и подобные — не зависят от
        # целевой платформы, берём у настоящего host llvm-config.
        #
        # НАЙДЕНО РЕАЛЬНОЙ ПРОВЕРКОЙ: этот путь может незаметно протащить
        # "-lffi" в финальную линковку — host (Homebrew) llvm-config
        # сообщает флаги, верные ДЛЯ ХОСТА (macOS), но libffi для
        # Android-таргета в NDK попросту не существует (подтверждено —
        # стандартный набор библиотек NDK sysroot: libc, libm, libdl,
        # libstdc++, libz — libffi там нет никогда). Не важно, через
        # какой именно флаг (--system-libs в другом порядке аргументов,
        # --ldflags или что-то ещё) это протекает — фильтруем -lffi из
        # ЛЮБОГО вывода, попавшего в эту резервную ветку.
        # ЗАРАНЕЕ, тем же способом: наша Android-сборка LLVM собрана без
        # zlib/zstd (LLVM_ENABLE_ZLIB=OFF, LLVM_ENABLE_ZSTD=OFF на Этапе
        # 5) — но host llvm-config, попав в эту ветку, может сообщить о
        # них, если они включены в HOST-сборке. Фильтруем сразу, не
        # дожидаясь, пока проявится тем же образом, что и с -lffi.
        # ⚠️ Порядок замен важен и намеренно BSD-sed-совместимый (без \b —
        # это GNU-расширение, ненадёжное в системном /usr/bin/sed на
        # macOS): сначала убираем "-lzstd" целиком, ТОЛЬКО ПОТОМ "-lz" —
        # если поменять местами, "-lz" съел бы первую половину "-lzstd".
        "\$LLVM_HOST_CONFIG" "\$@" | sed -e 's/-lffi//g' -e 's/-lzstd//g' -e 's/-lz //g' -e 's/-lz\$//g' -e 's/-lxml2//g'
        ;;
esac
BRIDGE_EOF
chmod +x "$BRIDGE_DIR/llvm-config"
echo "✓ Мост создан: $BRIDGE_DIR/llvm-config"
echo "  ⚠️ Если сборка компилятора (Этап 9) провалится с ошибками линковки —"
echo "  скорее всего, дело именно в этом мосте (неполный/неточный набор"
echo "  флагов) — придётся донастраивать вручную по конкретной ошибке."
echo ""

# ---------------------------------------------------------------------
# Этап 8: линковщик для cargo (NDK-обёртка clang под aarch64-android).
# ---------------------------------------------------------------------
echo "── Этап 8/10: настройка cargo для кросс-линковки ──"

# НОВОЕ: НАЙДЕНО РЕАЛЬНОЙ ПРОВЕРКОЙ — "undefined symbol: __clear_cache" при
# линковке. Это функция compiler-rt builtins (обслуживает очистку
# инструкционного кэша на ARM — нужна LLVM самому, независимо от нашего
# кода). Rust добавляет "-nodefaultlibs" при линковке под Android, что
# убирает автоматическое подключение этой библиотеки, которое clang обычно
# делает сам. Файл есть в самом NDK — ищем его явно (путь зависит от
# версии clang внутри NDK, поэтому через find, а не жёстко зашитый путь) и
# линкуем напрямую.
FFI_BUILTINS_LIB=$(find "$NDK_PATH" -name "libclang_rt.builtins-aarch64-android.a" 2>/dev/null | head -1)
if [ -z "$FFI_BUILTINS_LIB" ]; then
    echo "ОШИБКА: не нашёл libclang_rt.builtins-aarch64-android.a внутри NDK."
    echo "Поищи вручную: find \"$NDK_PATH\" -name 'libclang_rt.builtins-aarch64-android.a'"
    exit 1
fi
echo "Найден compiler-rt builtins: $FFI_BUILTINS_LIB"

mkdir -p "$PROJECT_ROOT/.cargo"
cat > "$PROJECT_ROOT/.cargo/config.toml" << CARGO_EOF
[target.aarch64-linux-android]
linker = "$NDK_CLANG_BIN/aarch64-linux-android23-clang"
ar = "$NDK_CLANG_BIN/llvm-ar"
rustflags = ["-C", "link-arg=$FFI_BUILTINS_LIB"]
CARGO_EOF
echo "✓ .cargo/config.toml настроен (linker: $NDK_CLANG_BIN/aarch64-linux-android23-clang)"
echo ""

# ---------------------------------------------------------------------
# Этап 9: сама сборка компилятора "Сфера" под aarch64-linux-android.
# ---------------------------------------------------------------------
echo "── Этап 9/10: cargo build --release --target aarch64-linux-android ──"
export LLVM_SYS_180_PREFIX="$WORK_DIR/llvm-config-android-bridge"
export PATH="$NDK_CLANG_BIN:$PATH"
export CC_aarch64_linux_android="$NDK_CLANG_BIN/aarch64-linux-android23-clang"
export CXX_aarch64_linux_android="$NDK_CLANG_BIN/aarch64-linux-android23-clang++"
export AR_aarch64_linux_android="$NDK_CLANG_BIN/llvm-ar"

cargo build --release --target aarch64-linux-android --bin запустить

FINAL_BINARY="$PROJECT_ROOT/target/aarch64-linux-android/release/запустить"
if [ ! -f "$FINAL_BINARY" ]; then
    echo "ОШИБКА: сборка как будто прошла, но бинарник не найден по пути $FINAL_BINARY"
    exit 1
fi
echo "✓ Компилятор собран: $FINAL_BINARY"
echo ""

# ---------------------------------------------------------------------
# Этап 10: проверка архитектуры итогового файла.
# ---------------------------------------------------------------------
echo "── Этап 10/10: проверка результата ──"
file "$FINAL_BINARY"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Готово (если не было ошибок выше)."
echo "  Бинарник: $FINAL_BINARY"
echo ""
echo "  Следующий шаг — зашить его в APK как fake-.so в jniLibs/"
echo "  arm64-v8a/ (тот же приём, что уже проверен и подтверждён"
echo "  рабочим для тестового бинарника — см. ИСТОРИЯ_РАЗРАБОТКИ.md)."
echo "  Ему тоже понадобится собственный, минимальный _start (linker"
echo "  ругался на отсутствие crtbegin_dynamic.o в этой же песочнице —"
echo "  на твоей NDK-сборке эти файлы, скорее всего, будут на месте,"
echo "  раз NDK установлен полностью, но если линковка самого"
echo "  компилятора тоже потребует -nostartfiles — попробуй тот же"
echo "  подход, что уже сработал для тестового бинарника."
echo "════════════════════════════════════════════════════════════"
