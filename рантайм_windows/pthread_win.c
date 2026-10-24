/* pthread_win.c — НАЙДЕНО РЕАЛЬНОЙ ПРОВЕРКОЙ НА WINDOWS: codegen.rs
 * безусловно объявляет и вызывает pthread_create/pthread_join/
 * pthread_mutex_* и pthread_cond_* в обёртке main КАЖДОЙ собранной
 * программы — даже такой простой, как "привет.код", которая вообще не
 * использует потоки (см. комментарий в codegen.rs у инициализации
 * sfera_детерм_мьютекс/sfera_детерм_cond: "безусловно, как и у
 * argc/argv — дешёво, безвредно, даже если программа ни разу не
 * использует 'детерминировано'"). На Linux/macOS это работает само —
 * там pthread — часть системной libc. На чистом Windows (MSVC) такой
 * библиотеки нет вообще, отсюда "unresolved external symbol
 * pthread_mutex_init" при линковке через обычный clang/link.exe.
 *
 * Этот файл — маленькая, самодостаточная реализация ТОЛЬКО тех
 * pthread-функций, которые реально вызывает codegen.rs (см. список
 * add_function в src/codegen.rs), через настоящие примитивы Win32
 * (CreateThread, CRITICAL_SECTION, CONDITION_VARIABLE) — не сторонняя
 * библиотека (ни MinGW winpthreads, ни pthreads4w), чтобы не добавлять
 * внешнюю зависимость для установки на Windows.
 *
 * Совместимость размеров: codegen.rs резервирует 128 байт под
 * pthread_mutex_t и 128 байт под pthread_cond_t (см. комментарий
 * "запас ради переносимости" там же) — этого с большим запасом
 * достаточно для CRITICAL_SECTION (40 байт на x64) и CONDITION_VARIABLE
 * (8 байт на x64). "pthread_t" в codegen.rs — это ОДНО значение
 * размером с указатель (alloca байт_указатель, см.
 * "буфер_id_потока") — ровно под HANDLE.
 *
 * Собирается установить-windows.ps1 один раз в pthread_win.o и
 * подключается компилятором автоматически при финальной линковке
 * КАЖДОЙ программы на Сфере — см. main.rs, найти_pthread_win_объектник
 * и слинковать_исполняемый_файл.
 */

#include <winsock2.h>
#include <windows.h>
#include <stdlib.h>

typedef void *(*sfera_функция_потока)(void *);

struct sfera_старт_потока {
    sfera_функция_потока функция;
    void *аргумент;
};

/* CreateThread ожидает "DWORD (WINAPI*)(LPVOID)", а codegen.rs
 * генерирует функции потока как "i8* (i8*)" (как и весь остальной FFI
 * в проекте — единая модель "непрозрачного указателя"). Эта маленькая
 * функция-переходник — единственное место, где приходится примирить
 * два разных соглашения о возвращаемом значении: результат настоящей
 * функции потока осознанно отбрасывается (как и раньше, на
 * Linux/macOS — pthread_join тоже вызывается с retval = NULL, язык
 * сейчас не пробрасывает результат потока наружу). */
static DWORD WINAPI sfera_переходник_потока(LPVOID параметр) {
    struct sfera_старт_потока *старт = (struct sfera_старт_потока *)параметр;
    sfera_функция_потока функция = старт->функция;
    void *аргумент = старт->аргумент;
    free(старт);
    функция(аргумент);
    return 0;
}

int pthread_create(void **thread, void *attr, sfera_функция_потока start_routine, void *arg) {
    (void)attr;
    struct sfera_старт_потока *старт = (struct sfera_старт_потока *)malloc(sizeof(*старт));
    if (!старт) {
        return 1;
    }
    старт->функция = start_routine;
    старт->аргумент = arg;
    HANDLE поток = CreateThread(NULL, 0, sfera_переходник_потока, старт, 0, NULL);
    if (поток == NULL) {
        free(старт);
        return 1;
    }
    *thread = (void *)поток;
    return 0;
}

int pthread_join(void *thread, void **retval) {
    (void)retval;
    HANDLE поток = (HANDLE)thread;
    WaitForSingleObject(поток, INFINITE);
    CloseHandle(поток);
    return 0;
}

int pthread_mutex_init(void *m, void *attr) {
    (void)attr;
    InitializeCriticalSection((CRITICAL_SECTION *)m);
    return 0;
}

int pthread_mutex_lock(void *m) {
    EnterCriticalSection((CRITICAL_SECTION *)m);
    return 0;
}

int pthread_mutex_unlock(void *m) {
    LeaveCriticalSection((CRITICAL_SECTION *)m);
    return 0;
}

int pthread_mutex_destroy(void *m) {
    DeleteCriticalSection((CRITICAL_SECTION *)m);
    return 0;
}

int pthread_cond_init(void *c, void *attr) {
    (void)attr;
    InitializeConditionVariable((CONDITION_VARIABLE *)c);
    return 0;
}

int pthread_cond_signal(void *c) {
    WakeConditionVariable((CONDITION_VARIABLE *)c);
    return 0;
}

int pthread_cond_broadcast(void *c) {
    WakeAllConditionVariable((CONDITION_VARIABLE *)c);
    return 0;
}

int pthread_cond_wait(void *c, void *m) {
    SleepConditionVariableCS((CONDITION_VARIABLE *)c, (CRITICAL_SECTION *)m, INFINITE);
    return 0;
}

/* Настоящие Win32 condition variables не требуют явного освобождения
 * ресурсов (в отличие от CRITICAL_SECTION) — безопасный no-op, но
 * функция всё равно должна существовать, раз codegen.rs её вызывает
 * (канал<T>.освободить()). */
int pthread_cond_destroy(void *c) {
    (void)c;
    return 0;
}

/* ====================== Сокеты (Winsock) ======================
 *
 * сайт/сеть.код написан на POSIX-сокетах. На Windows те же функции живут
 * в ws2_32, но: (1) перед первым вызовом нужен WSAStartup; (2) SOCKET там
 * — 64-битный беззнаковый дескриптор, а закрывается он closesocket, не
 * close; (3) send/recv принимают и возвращают int, а не ssize_t. Чтобы
 * Сфера-код оставался одним на все платформы, сеть.код объявляет внешние
 * функции с ДВУМЯ именами ("как "send", "sfera_win_send"") — на Windows
 * компилятор берёт второе, то есть функции ниже. Дескрипторы в Сфере —
 * целое32: на практике хэндлы сокетов Windows небольшие, а
 * INVALID_SOCKET (~0) превращается в -1, как и ожидает код.
 */

static void __attribute__((constructor)) sfera_инициализация_сокетов(void) {
    WSADATA данные;
    WSAStartup(MAKEWORD(2, 2), &данные);
}

#define SFERA_СОКЕТ(x) ((SOCKET)(INT_PTR)(x))

int sfera_win_socket(int домен, int тип, int протокол) {
    return (int)socket(домен, тип, протокол);
}

int sfera_win_connect(int s, const char *адрес, int размер) {
    return connect(SFERA_СОКЕТ(s), (const struct sockaddr *)адрес, размер);
}

int sfera_win_bind(int s, const char *адрес, int размер) {
    return bind(SFERA_СОКЕТ(s), (const struct sockaddr *)адрес, размер);
}

int sfera_win_listen(int s, int очередь) {
    return listen(SFERA_СОКЕТ(s), очередь);
}

int sfera_win_accept(int s, char *адрес_клиента, char *размер_адреса) {
    return (int)accept(SFERA_СОКЕТ(s), (struct sockaddr *)адрес_клиента, (int *)размер_адреса);
}

long long sfera_win_send(int s, const char *буфер, long long размер, int флаги) {
    if (размер > 0x7fffffff) размер = 0x7fffffff;
    return send(SFERA_СОКЕТ(s), буфер, (int)размер, флаги);
}

long long sfera_win_recv(int s, char *буфер, long long размер, int флаги) {
    if (размер > 0x7fffffff) размер = 0x7fffffff;
    return recv(SFERA_СОКЕТ(s), буфер, (int)размер, флаги);
}

int sfera_win_close(int s) {
    return closesocket(SFERA_СОКЕТ(s));
}

/* Константы SOL_SOCKET/SO_REUSEADDR у Windows другие, и смысл SO_REUSEADDR
 * другой (разрешает занять порт чужого процесса). Windows и так позволяет
 * заново занять порт после остановки сервера — поэтому это no-op. */
int sfera_win_setsockopt(int s, int уровень, int опция, const char *значение, int размер) {
    (void)s; (void)уровень; (void)опция; (void)значение; (void)размер;
    return 0;
}

int sfera_win_htons(int значение) {
    return (int)htons((u_short)значение);
}
