# запуск_х86_64.s — (стартовый код без вывода на экран и без printf: всё остальное делает рантайм на Сфере)
# Исходный комментарий ядро_64.s:
# ядро_64.s — второй, решающий шаг к настоящей загрузке "на голом
# железе": полный переход из 32-битного защищённого режима (в котором
# Multiboot передаёт управление) в 64-битный (long mode) — тот самый,
# в котором работает весь наш компилятор — чтобы наконец вызвать
# настоящую, скомпилированную языком Сфера функцию "main" БЕЗ какой-либо
# операционной системы вообще.
#
# Последовательность перехода — хорошо документированная (см. OSDev
# wiki "Setting Up Long Mode"), но объёмная: настройка таблиц страниц,
# включение PAE, загрузка адреса таблиц в CR3, включение long mode через
# регистр EFER, включение самой страничной адресации, и, наконец,
# загрузка 64-битной GDT с дальним переходом в 64-битный код.

.intel_syntax noprefix

.set MULTIBOOT_МАГИЯ, 0x1BADB002
.set MULTIBOOT_ФЛАГИ, 0x0
.set MULTIBOOT_КОНТРОЛЬНАЯ_СУММА, -(MULTIBOOT_МАГИЯ + MULTIBOOT_ФЛАГИ)

.section .multiboot,"a"
.align 4
    .long MULTIBOOT_МАГИЯ
    .long MULTIBOOT_ФЛАГИ
    .long MULTIBOOT_КОНТРОЛЬНАЯ_СУММА

.section .bss
.align 16
стек_снизу:
    .skip 16384
стек_сверху:

# Таблицы страниц для перехода в long mode — используем страницы по 2 МБ
# ("huge pages"), это позволяет обойтись всего одной записью на каждом
# уровне вместо полной четырёхуровневой иерархии с 4 КБ страницами.
# Каждая таблица обязана быть выровнена по границе 4 КБ.
.align 4096
пмл4:
    .skip 4096
пдпт:
    .skip 4096
пд:
    .skip 4096
пд_высокий:
    .skip 4096
.align 8
инфо_загрузчика:
    .skip 8

# НОВОЕ: область памяти для распределителя структур (см. подробное
# объяснение в арена_распределитель.код — тот же самый bump allocator,
# написанный на языке Сфера, что уже работал в автономном Linux-режиме,
# просто теперь со своей, отдельной ареной прямо здесь). Помещается в
# только что расширенное отображение памяти (0-4 МБ).
.align 16
арена64:
    .skip 1048576

.section .rodata
.align 8
подпись_результата:
    .asciz "\nResult: "

.align 8
gdt64:
    .quad 0                              # обязательный нулевой дескриптор
    .quad 0x00209A0000000000              # 64-битный код: present, исполняемый, кольцо 0, бит L (long mode)
    .quad 0x0000920000000000              # данные: present, доступен для записи, кольцо 0
    .quad 0x0000F20000000000              # 0x18: данные пользователя (кольцо 3)
    .quad 0x0020FA0000000000              # 0x20: 64-битный код пользователя (кольцо 3)
gdt64_tss:
    .quad 0                               # 0x28: дескриптор TSS (16 байт) — заполняется в sfera_tss_init
    .quad 0
gdt64_конец:
gdt64_указатель:
    .word gdt64_конец - gdt64 - 1
    .quad gdt64

.section .text
.global _start
.code32
_start:
    mov dword ptr [инфо_загрузчика], ebx
    mov esp, offset стек_сверху

    # --- Шаг 1: строим таблицы страниц (identity mapping первых 2 МБ) ---
    # PML4[0] -> PDPT (present + доступна для записи)
    mov eax, offset пдпт
    or eax, 0b11
    mov dword ptr [пмл4], eax
    mov dword ptr [пмл4 + 4], 0

    # PDPT[0] -> PD (present + доступна для записи)
    mov eax, offset пд
    or eax, 0b11
    mov dword ptr [пдпт], eax
    mov dword ptr [пдпт + 4], 0

    # PD[0] и PD[1] -> две страницы по 2 МБ (0-2МБ и 2-4МБ), начиная с
    # физического адреса 0 (present + доступна для записи + флаг
    # "страница 2 МБ") — расширено с одной страницы до двух, чтобы
    # осталось место для арены распределителя памяти (см. ниже) —
    # ядро загружается по адресу 1 МБ, значит одной страницы (0-2МБ)
    # было бы впритык.
    # PD: первый гигабайт целиком (512 страниц по 2 МБ), физический адрес = виртуальному
    xor ecx, ecx
1:  mov eax, ecx
    shl eax, 21
    or eax, 0x83
    mov dword ptr [пд + ecx * 8], eax
    mov dword ptr [пд + ecx * 8 + 4], 0
    inc ecx
    cmp ecx, 512
    jne 1b

    # PDPT[3] -> таблица на 1 ГБ (адреса 0xC0000000–0xFFFFFFFF, там видеопамять и устройства PCI);
    # страницы по 2 МБ, без кэширования (бит PCD)
    mov eax, offset пд_высокий
    or eax, 0b11
    mov dword ptr [пдпт + 24], eax
    mov dword ptr [пдпт + 28], 0
    xor ecx, ecx
2:  mov eax, ecx
    shl eax, 21
    add eax, 0xC0000000
    or eax, 0x93
    mov dword ptr [пд_высокий + ecx * 8], eax
    mov dword ptr [пд_высокий + ecx * 8 + 4], 0
    inc ecx
    cmp ecx, 512
    jne 2b

    # --- Шаг 2: включаем PAE (Physical Address Extension) — бит 5 в CR4 ---
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    # --- Шаг 3: загружаем физический адрес PML4 в CR3 ---
    mov eax, offset пмл4
    mov cr3, eax

    # --- Шаг 4: включаем Long Mode — бит LME в MSR EFER (адрес 0xC0000080) ---
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    # --- Шаг 5: включаем саму страничную адресацию — бит PG в CR0 (бит 31) ---
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    # --- Шаг 6: загружаем 64-битную GDT и делаем дальний переход ---
    # Именно этот переход и переключает процессор в полноценный
    # 64-битный режим выполнения — до этого момента, несмотря на все
    # предыдущие шаги, инструкции всё ещё декодируются как 32-битные.
    lgdt [gdt64_указатель]
    jmp 0x08:точка_входа_64

.code64
точка_входа_64:
    # Настраиваем сегментные регистры данных на наш сегмент данных
    # (индекс 2 в GDT, то есть смещение 2*8=0x10) — в 64-битном режиме
    # они по большей части игнорируются процессором, но должны быть
    # валидными, иначе последующие инструкции с памятью могут вызвать
    # исключение.
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax

    # Тот же стек, что использовался в 32-битном коде, — он уже
    # идентично отображён (identity-mapped) и полностью годится для
    # использования как RSP в 64-битном режиме.
    mov rsp, offset стек_сверху

    # ЗДЕСЬ И ПРОИСХОДИТ ГЛАВНОЕ: вызов настоящей, скомпилированной
    # языком Сфера функции "main" — БЕЗ Linux, БЕЗ libc, БЕЗ вообще
    # какой-либо операционной системы, только что включённый нами самими
    # 64-битный режим процессора.
    # Включаем SSE: без этого любые дробные вычисления вызывают исключение
    # «неверная команда» (процессор в long mode считает дробные числа через SSE).
    mov rax, cr0
    and ax, 0xFFFB          # CR0.EM = 0 (эмуляции сопроцессора нет)
    or ax, 0x2              # CR0.MP = 1
    mov cr0, rax
    mov rax, cr4
    or ax, 0x600            # CR4.OSFXSR и CR4.OSXMMEXCPT
    mov cr4, rax

    call sfera_idt_init
    call sfera_tss_init
    call main

остановка:
    cli
    hlt
    jmp остановка

# Куча для распределителя на Сфере (стандартная_библиотека/голое_железо.код).
.global sfera_куча_начало
sfera_куча_начало:
    lea rax, [rip + арена64]
    ret

.global sfera_куча_размер
sfera_куча_размер:
    mov rax, 1048576
    ret


# ---------------- Прерывания ----------------
# Таблица дескрипторов прерываний (IDT): 256 записей по 16 байт.
.section .bss
.align 16
idt:
    .skip 4096
idt_указатель:
    .skip 16

.section .text
# rdx = адрес записи в IDT, rax = адрес обработчика
записать_ворота:
    mov word ptr [rdx], ax
    mov word ptr [rdx + 2], 0x08          # сегмент кода
    mov byte ptr [rdx + 4], 0
    mov byte ptr [rdx + 5], 0x8E          # present, кольцо 0, «шлюз прерывания»
    mov r8, rax
    shr r8, 16
    mov word ptr [rdx + 6], r8w
    shr r8, 16
    mov dword ptr [rdx + 8], r8d
    mov dword ptr [rdx + 12], 0
    ret

.macro вектор номер, метка
    lea rax, [rip + \метка]
    lea rdx, [rip + idt + \номер * 16]
    call записать_ворота
.endm

.global sfera_idt_init
sfera_idt_init:
    # все 256 прерываний по умолчанию ведут в «аварийный» обработчик
    lea rax, [rip + прерывание_авария]
    lea rdx, [rip + idt]
    mov rcx, 256
1:  call записать_ворота
    add rdx, 16
    dec rcx
    jnz 1b
    вектор 14, прерывание_страницы        # ошибка страницы
    вектор 32, прерывание_таймер          # IRQ0 — таймер
    вектор 33, прерывание_клавиатура      # IRQ1 — клавиатура
    вектор 128, прерывание_сисвызов       # int 0x80 — системный вызов
    mov byte ptr [rip + idt + 128 * 16 + 5], 0xEE   # кольцо 3 разрешено вызывать: present, DPL=3, шлюз прерывания
    lea rax, [rip + idt]
    mov word ptr [rip + idt_указатель], 4095
    mov qword ptr [rip + idt_указатель + 2], rax
    lidt [rip + idt_указатель]
    ret

# Любое неожиданное прерывание или исключение: пишем «!» в COM1 и останавливаемся.
прерывание_авария:
    mov dx, 0x3F8
    mov al, 33
    out dx, al
    cli
1:  hlt
    jmp 1b

# Вход в прерывание: сохраняем регистры и состояние сопроцессора, зовём функцию Сферы.
.macro вход_в_прерывание функция
    push rbp
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov rbp, rsp
    and rsp, -16
    sub rsp, 512
    fxsave [rsp]
    call \функция
    fxrstor [rsp]
    mov rsp, rbp
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    pop rbp
    iretq
.endm

# Прерывание таймера — переключение задач. Сохраняем все регистры и состояние сопроцессора на стеке
# текущей задачи (кадр 640 байт: 512 — fxsave, 8 — выравнивание, 80 — регистры, 40 — кадр прерывания),
# зовём sfera_irq_timer(кадр) на Сфере и переходим на стек того кадра, который она вернёт.
# Если задач нет, функция возвращает тот же кадр.
прерывание_таймер:
    push rbp
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    sub rsp, 520
    fxsave [rsp]
    mov rdi, rsp
    call sfera_irq_timer
    mov rsp, rax
    fxrstor [rsp]
    add rsp, 520
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    pop rbp
    iretq
прерывание_клавиатура:
    вход_в_прерывание sfera_irq_kbd

# ---------------- Пользовательский режим (кольцо 3) ----------------
.section .bss
.align 16
tss:
    .skip 104
сохранённый_стек_ядра:
    .skip 8

.section .text
# Заполняет дескриптор TSS в GDT и загружает регистр задачи. При входе из кольца 3 процессор берёт стек ядра из tss.rsp0.
.global sfera_tss_init
sfera_tss_init:
    lea rax, [rip + tss]
    lea rdx, [rip + gdt64_tss]
    mov word ptr [rdx], 103
    mov word ptr [rdx + 2], ax
    shr rax, 16
    mov byte ptr [rdx + 4], al
    mov byte ptr [rdx + 5], 0x89          # present, TSS 64 бита (свободный)
    mov byte ptr [rdx + 6], 0
    mov byte ptr [rdx + 7], ah
    shr rax, 16
    mov dword ptr [rdx + 8], eax
    mov dword ptr [rdx + 12], 0
    mov ax, 0x28
    ltr ax
    ret

# sfera_войти_в_пользователя(вход, вершина_стека): переходит в кольцо 3 и возвращается, когда программа
# вызвала «выход» (или нарушила защиту): тогда возвращает код завершения.
.global "sfera_войти_в_пользователя"
"sfera_войти_в_пользователя":
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rip + сохранённый_стек_ядра], rsp
    mov rax, rsp
    and rax, -16
    lea rdx, [rip + tss]
    mov [rdx + 4], rax                    # rsp0: сюда процессор положит кадр при прерывании из кольца 3
    push 0x1B                             # ss пользователя
    push rsi                              # rsp пользователя
    push 0x202                            # rflags: прерывания разрешены
    push 0x23                             # cs пользователя
    push rdi                              # rip
    iretq

# Возврат из пользовательского режима в ядро (код завершения лежит по адресу 0x300E10).
выйти_из_пользователя:
    mov qword ptr [0x300E08], 0
    mov rax, [0x300E10]
    mov rsp, [rip + сохранённый_стек_ядра]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    sti
    ret

# Системный вызов int 0x80: rax — номер, rdi, rsi, rdx — параметры; результат в rax.
# Зовёт sfera_сисвызов_ядро(номер, а, б, в).
прерывание_сисвызов:
    push rbp
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rax
    mov rbp, rsp
    and rsp, -16
    sub rsp, 512
    fxsave [rsp]
    call "sfera_сисвызов_ядро"
    fxrstor [rsp]
    mov rsp, rbp
    cmp qword ptr [0x300E08], 0
    jne выйти_из_пользователя
    mov [rsp + 64], rax                   # результат — в сохранённый rax пользователя
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    pop rbp
    iretq

# Ошибка страницы: процессор кладёт в стек код ошибки; адрес обращения лежит в CR2.
# Вызываем sfera_pf(код_ошибки, адрес). Если функция вернулась, обращение повторяется.
прерывание_страницы:
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov rdi, [rbp + 8]
    mov rsi, cr2
    and rsp, -16
    sub rsp, 512
    fxsave [rsp]
    call sfera_pf
    cmp qword ptr [0x300E08], 0
    jne выйти_из_пользователя
    fxrstor [rsp]
    lea rsp, [rbp - 72]
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    pop rbp
    add rsp, 8
    iretq

# Для программы на Сфере: данные загрузчика, регистр CR3 и сброс записи в кэше страниц.
.global "sfera_инфо_загрузчика"
"sfera_инфо_загрузчика":
    mov eax, dword ptr [rip + инфо_загрузчика]
    ret
.global "sfera_cr3"
"sfera_cr3":
    mov rax, cr3
    ret
.global "sfera_сбросить_страницу"
"sfera_сбросить_страницу":
    invlpg [rdi]
    ret

# Адрес растрового шрифта для программы на Сфере.
.global "sfera_шрифт_адрес"
"sfera_шрифт_адрес":
    lea rax, [rip + sfera_font_8x16]
    ret

# Если программа не определила обработчики, ничего не делаем и подтверждаем прерывание.
.weak sfera_irq_timer
sfera_irq_timer:
    mov rax, rdi
    ret
.weak sfera_pf
sfera_pf:
    cli
1:  hlt
    jmp 1b
.weak "sfera_сисвызов_ядро"
"sfera_сисвызов_ядро":
    mov rax, -1
    ret
.weak sfera_irq_kbd
sfera_irq_kbd:
    ret

.section .note.GNU-stack,"",@progbits
