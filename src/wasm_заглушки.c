#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Заглушки для сборки Сферы под WebAssembly (WASI). Подключаются при линковке автоматически.
// Потоков в браузере нет, поэтому pthread-функции ничего не делают.
// Обёртка main в программах Сферы называется «main», а wasi-libc зовёт __main_argc_argv.
extern int sfera_main(int, char**) __asm__("main");
int __main_argc_argv(int a, char** b) { return sfera_main(a, b); }

int pthread_mutex_init(void* m, const void* a) { return 0; }
int pthread_mutex_lock(void* m) { return 0; }
int pthread_mutex_unlock(void* m) { return 0; }
int pthread_mutex_destroy(void* m) { return 0; }
int pthread_cond_init(void* c, const void* a) { return 0; }
int pthread_cond_signal(void* c) { return 0; }
int pthread_cond_broadcast(void* c) { return 0; }
int pthread_cond_wait(void* c, void* m) { return 0; }
int pthread_cond_destroy(void* c) { return 0; }

// Обёртки с 64-битными числами: так libc объявлена в коде, который выдаёт компилятор Сферы.
void* sfera_wasm_malloc(long long n) { return malloc((size_t)n); }
void* sfera_wasm_memcpy(void* a, const void* b, long long n) { return memcpy(a, b, (size_t)n); }
void* sfera_wasm_memmove(void* a, const void* b, long long n) { return memmove(a, b, (size_t)n); }
long long sfera_wasm_strlen(const char* s) { return (long long)strlen(s); }
long long sfera_wasm_strtol(const char* s, char** end, int base) { return strtoll(s, end, base); }
int sfera_wasm_snprintf(char* buf, long long n, const char* fmt, ...) {
    va_list v; va_start(v, fmt);
    int r = vsnprintf(buf, (size_t)n, fmt, v);
    va_end(v);
    return r;
}
int sfera_wasm_fseek(FILE* f, long long off, int whence) { return fseek(f, (long)off, whence); }
long long sfera_wasm_ftell(FILE* f) { return (long long)ftell(f); }
long long sfera_wasm_fread(void* p, long long a, long long b, FILE* f) { return (long long)fread(p, (size_t)a, (size_t)b, f); }
long long sfera_wasm_fwrite(const void* p, long long a, long long b, FILE* f) { return (long long)fwrite(p, (size_t)a, (size_t)b, f); }
