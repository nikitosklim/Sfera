# загрузчик_uefi.s — UEFI-приложение: загружает ядро Сферы на компьютерах и в виртуальных машинах с UEFI.
#
# Что делает:
#   1. находит экран (Graphics Output Protocol) и ставит режим 800×600, если он есть;
#   2. резервирует у прошивки память с адреса 1 МБ (5 МБ) — туда ядро и лежит;
#   3. обнуляет её и копирует ядро (оно вшито в этот файл);
#   4. читает карту памяти и считает, сколько непрерывной обычной памяти идёт от 1 МБ;
#   5. выходит из служб UEFI и передаёт управление ядру (_start_uefi) — «сведения загрузчика»
#      лежат по адресу 0x2F0000 в том же виде, что у Multiboot (флаги, память, адрес и длина строки экрана).
# (Метки — латиницей: ассемблер clang, нужный для PE-файла, не принимает кириллицу в именах.)
# Соглашение вызовов UEFI (Microsoft x64): аргументы в rcx, rdx, r8, r9, дальше на стеке после 32 байт «теневого места».
# Собирается скриптом собрать_uefi.sh (clang + lld-link).

.intel_syntax noprefix
.include "точка.inc"          # .set ENTRY_POINT, адрес _start_uefi в ядре
.include "сообщения.inc"      # строки UTF-16, их делает собрать_uefi.sh

.set KERNEL_ADDR, 0x100000
.set KERNEL_PAGES, 1280        # 5 МБ: ядро, его bss, арена и стек, таблицы страниц
.set INFO, 0x2F0000
.set SCREEN_W, 800
.set SCREEN_H, 600

.text
.globl efi_main
efi_main:
    sub rsp, 0x78
    mov r14, rcx                       # ImageHandle
    mov r12, rdx                       # SystemTable
    mov r13, [rdx + 0x60]              # BootServices
    lea rdx, [rip + msg_start]
    call print

    # ---- экран ----
    xor r15, r15                       # r15 = указатель на GOP (0 — экрана нет)
    lea rcx, [rip + guid_gop]
    xor edx, edx
    lea r8, [rsp + 0x30]
    call [r13 + 0x140]                 # LocateProtocol
    test rax, rax
    jnz 5f
    mov r15, [rsp + 0x30]
    # ищем режим 800×600 (цвет 32 бита: порядок RGB или BGR)
    mov rax, [r15 + 0x18]
    mov esi, [rax]                     # MaxMode
    xor edi, edi
1:  cmp edi, esi
    jae 4f
    mov rcx, r15
    mov edx, edi
    lea r8, [rsp + 0x38]               # размер сведений
    lea r9, [rsp + 0x40]               # указатель на сведения
    call [r15]                         # QueryMode
    test rax, rax
    jnz 3f
    mov rax, [rsp + 0x40]
    cmp dword ptr [rax + 4], SCREEN_W
    jne 3f
    cmp dword ptr [rax + 8], SCREEN_H
    jne 3f
    cmp dword ptr [rax + 0xC], 2       # формат пикселя: 0 или 1 (RGB/BGR); 2 — маска, 3 — только Blt
    jae 3f
    mov rcx, r15
    mov edx, edi
    call [r15 + 8]                     # SetMode
    jmp 4f
3:  inc edi
    jmp 1b
4:
5:
    # ---- память для ядра ----
    mov qword ptr [rsp + 0x58], KERNEL_ADDR
    mov ecx, 2                         # AllocateAddress
    mov edx, 1                         # EfiLoaderCode (не «данные»: прошивка запрещает исполнять код из данных, NX)
    mov r8d, KERNEL_PAGES
    lea r9, [rsp + 0x58]
    call [r13 + 0x28]                  # AllocatePages
    test rax, rax
    jz 6f
    lea rdx, [rip + msg_nomem]
    call print
    jmp halt_forever
6:
    # обнуляем и копируем ядро
    mov edi, KERNEL_ADDR
    mov ecx, KERNEL_PAGES * 512
    xor eax, eax
    cld
    rep stosq
    mov edi, KERNEL_ADDR
    lea rsi, [rip + kernel_start]
    lea rcx, [rip + kernel_end]
    sub rcx, rsi                       # размер вшитого ядра
    rep movsb

    # ---- сведения для ядра ----
    mov edi, INFO
    mov ecx, 32
    xor eax, eax
    rep stosq
    mov dword ptr [INFO], 1                    # флаги: есть объём памяти
    test r15, r15
    jz 7f
    mov rax, [r15 + 0x18]                          # Mode
    mov rdx, [rax + 8]                             # Info
    mov rcx, [rax + 0x18]                          # адрес видеопамяти
    mov dword ptr [INFO + 88], ecx
    mov dword ptr [INFO + 92], 0
    mov ecx, [rdx + 0x20]                          # пикселей в строке
    shl ecx, 2
    mov dword ptr [INFO + 96], ecx
    mov dword ptr [INFO + 100], 0
    or dword ptr [INFO], 4096                  # флаг: сведения об экране есть
7:
    # ---- карта памяти и выход из служб UEFI (при неудаче — одна повторная попытка) ----
    mov dword ptr [rsp + 0x60], 2
8:  mov qword ptr [rsp + 0x38], 65536              # размер буфера
    lea rcx, [rsp + 0x38]
    lea rdx, [rip + memmap]
    lea r8, [rsp + 0x40]                           # ключ карты
    lea r9, [rsp + 0x48]                           # размер описания
    lea rax, [rsp + 0x50]
    mov [rsp + 0x20], rax                          # версия
    call [r13 + 0x38]                              # GetMemoryMap
    test rax, rax
    jnz err_map
    call count_mem                                 # rbx, rbp = лучший участок свободной памяти
    mov dword ptr [INFO + 0x70], ebx
    mov dword ptr [INFO + 0x74], ebp
    test ebp, ebp
    jz 10f
    mov eax, ebp
    sub eax, KERNEL_ADDR
    shr eax, 10                                    # для совместимости с Multiboot: КБ выше 1 МБ
    mov dword ptr [INFO + 8], eax
    or dword ptr [INFO], 0x40000000                # флаг: есть участок свободной памяти (+0x70 начало, +0x74 конец)
10:
    mov rcx, r14
    mov rdx, [rsp + 0x40]
    call [r13 + 0xE8]                              # ExitBootServices
    test rax, rax
    jz 9f
    dec dword ptr [rsp + 0x60]
    jnz 8b
    jmp err_map
9:
    cli
    mov ebx, INFO
    mov rax, ENTRY_POINT
    jmp rax

err_map:
    lea rdx, [rip + msg_map]
    call print
halt_forever:
    hlt
    jmp halt_forever

# rdx = строка UTF-16; печатает на консоль прошивки (латиницей — шрифта с кириллицей там может не быть)
print:
    sub rsp, 0x28
    mov rcx, [r12 + 0x40]              # ConOut
    test rcx, rcx
    jz 1f
    call [rcx + 8]                     # OutputString
1:  add rsp, 0x28
    ret

# Ищет самый большой непрерывный участок памяти, который после выхода из UEFI свободен, в пределах от 6 МБ до 1 ГБ
# (ядро занимает 1–6 МБ, а выше 1 ГБ у него нет отображения). Вход: карта в буфере memmap; размер карты и размер описания
# лежат в кадре efi_main ([rsp+0x40] и [rsp+0x50] — внутри функции, из-за адреса возврата).
# Выход: rbx = начало участка, rbp = конец (0 — не нашли). Портит rax, rcx, rdx, rsi, rdi, r8–r11.
count_mem:
    mov r8, [rsp + 0x40]               # размер карты в байтах
    mov r9, [rsp + 0x50]               # размер одного описания
    lea rdi, [rip + memmap]
    xor ecx, ecx                       # смещение в карте
    xor r10d, r10d                     # начало текущего непрерывного участка
    xor r11d, r11d                     # конец текущего участка (0 — участка нет)
    xor ebx, ebx
    xor ebp, ebp
1:  cmp rcx, r8
    jae 9f
    lea rax, [rdi + rcx]
    mov edx, [rax]                     # свободны после выхода: загрузчик (1, 2), службы (3, 4), обычная (7)
    cmp edx, 1
    je 2f
    cmp edx, 2
    je 2f
    cmp edx, 3
    je 2f
    cmp edx, 4
    je 2f
    cmp edx, 7
    je 2f
    xor r11d, r11d                     # другой тип — участок оборвался
    jmp 8f
2:  mov rsi, [rax + 8]                 # начало описания
    mov rdx, [rax + 24]
    shl rdx, 12
    add rdx, rsi                       # конец описания
    test r11, r11
    jz 3f
    cmp rsi, r11
    je 4f                              # описание продолжает текущий участок
3:  mov r10, rsi                       # иначе начинается новый
4:  mov r11, rdx
    mov rsi, r10                       # обрезаем участок до [6 МБ, 1 ГБ)
    mov rax, 0x600000
    cmp rsi, rax
    jae 5f
    mov rsi, rax
5:  mov rdx, r11
    mov rax, 0x40000000
    cmp rdx, rax
    jbe 6f
    mov rdx, rax
6:  cmp rdx, rsi
    jbe 8f                             # после обрезки ничего не осталось
    mov rax, rdx
    sub rax, rsi
    sub rax, rbp
    add rax, rbx                       # (размер этого участка) − (размер лучшего)
    jle 8f
    mov rbx, rsi
    mov rbp, rdx
8:  add rcx, r9
    jmp 1b
9:  ret

.section .rdata,"dr"
.align 8
guid_gop:                              # 9042a9de-23dc-4a38-96fb-7aded080516a
    .long 0x9042a9de
    .word 0x23dc, 0x4a38
    .byte 0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a
.align 16
kernel_start:
    .incbin "ядро_плоское.bin"
kernel_end:

.section .bss,"bw"
.align 16
memmap:
    .skip 65536
