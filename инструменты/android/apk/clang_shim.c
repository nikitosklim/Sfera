/* clang_shim.c — замена clang на телефоне.
 *
 * Компилятор Сферы после генерации объектного файла вызывает «clang файл.o -o программа ...».
 * На устройстве настоящего clang нет, зато в APK лежит lld (как liblld.so) и файлы
 * Android NDK (libsfera_*.so — переименованные crtbegin/crtend/libc/libm/libdl,
 * чтобы Android распаковал их при установке). Шим превращает вызов в запуск lld.
 *
 * Установленные файлы лежат рядом с самим шимом: /proc/self/exe → каталог библиотек.
 * Отладка: переменная SFERA_SHIM_DEBUG=1 печатает итоговую команду lld.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char *join(const char *dir, const char *name) {
    size_t n = strlen(dir) + strlen(name) + 2;
    char *p = malloc(n);
    snprintf(p, n, "%s/%s", dir, name);
    return p;
}

int main(int argc, char **argv) {
    char self[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (len <= 0) { perror("clang-shim: readlink"); return 1; }
    self[len] = 0;
    char *slash = strrchr(self, '/');
    if (!slash) return 1;
    *slash = 0;
    const char *lib = self;

    char **args = calloc((size_t)argc + 32, sizeof(char *));
    int k = 0;
    args[k++] = join(lib, "liblld.so");
    args[k++] = "-flavor";
    args[k++] = "gnu";
    args[k++] = "-pie";
    args[k++] = "--dynamic-linker=/system/bin/linker64";
    args[k++] = "-z";
    args[k++] = "now";
    args[k++] = "--eh-frame-hdr";
    args[k++] = "-L";
    args[k++] = (char *)lib;
    args[k++] = join(lib, "libsfera_crtbegin.so");

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "-o") && i + 1 < argc) { args[k++] = "-o"; args[k++] = argv[++i]; continue; }
        if (!strcmp(a, "-no-pie") || !strcmp(a, "-nodefaultlibs") || !strcmp(a, "-fuse-ld=lld") ||
            !strcmp(a, "-fPIC") || !strcmp(a, "-pie") || !strcmp(a, "-lpthread") || !strcmp(a, "-lrt") ||
            !strncmp(a, "--target=", 9) || !strncmp(a, "--sysroot=", 10)) continue;
        if (!strcmp(a, "-lc") || !strcmp(a, "-lm") || !strcmp(a, "-ldl")) continue; /* добавим ниже */
        args[k++] = argv[i];
    }

    args[k++] = join(lib, "libsfera_c.so");
    args[k++] = join(lib, "libsfera_m.so");
    args[k++] = join(lib, "libsfera_dl.so");
    args[k++] = join(lib, "libsfera_builtins.so");
    args[k++] = join(lib, "libsfera_crtend.so");
    args[k] = NULL;

    if (getenv("SFERA_SHIM_DEBUG")) {
        for (int i = 0; i < k; i++) fprintf(stderr, "%s ", args[i]);
        fprintf(stderr, "\n");
    }
    execv(args[0], args);
    perror("clang-shim: execv lld");
    return 1;
}
