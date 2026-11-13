# второй_этап.s — второй этап загрузчика Сферы.
#
# Работает по адресу 0x7E00, начинает в 16-битном «реальном» режиме. Что делает:
#   1. включает адресную линию A20 (доступ к памяти выше 1 МБ);
#   2. узнаёт у BIOS объём памяти (функция E820);
#   3. читает ядро с диска в память по адресу 0x20000;
#   4. переходит в 32-битный защищённый режим, копирует ядро на 1 МБ и обнуляет его область bss;
#   5. передаёт ядру управление так же, как это делает загрузчик по стандарту Multiboot
#      (eax = 0x2BADB002, ebx = адрес сведений), поэтому то же ядро грузится и этим загрузчиком, и QEMU напрямую.
#
# Числа ниже подставляет сборочный скрипт: ЯДРО_СЕКТОРОВ, ЯДРО_ПЕРВЫЙ_СЕКТОР, ЯДРО_ДВОЙНЫХ_СЛОВ,
# ЯДРО_КОНЕЦ_ОБРАЗА, BSS_ДВОЙНЫХ_СЛОВ, ЯДРО_ВХОД.

.intel_syntax noprefix
.code16
.section .text
.global _start
_start:
    mov byte ptr [диск], dl

    in al, 0x92                     # включаем A20 «быстрым» способом
    or al, 2
    and al, 0xFE
    out 0x92, al

    # сведения для ядра по адресу 0x6000: флаги, нижняя память (КБ), верхняя память (КБ)
    mov dword ptr [0x6000], 1
    mov dword ptr [0x6004], 639
    mov dword ptr [0x6008], 0
    mov di, 0x6058                  # поля экрана — нули, пока не найдём режим
    xor eax, eax
    mov ecx, 6
    cld
    rep stosd
    xor ebx, ebx
    mov di, 0x500
1:  mov eax, 0xE820
    mov edx, 0x534D4150
    mov ecx, 24
    int 0x15
    jc 3f
    cmp eax, 0x534D4150
    jne 3f
    cmp dword ptr [di], 0x100000    # нужна свободная область, начинающаяся с 1 МБ
    jne 2f
    cmp dword ptr [di + 4], 0
    jne 2f
    cmp dword ptr [di + 16], 1
    jne 2f
    mov eax, dword ptr [di + 8]
    shr eax, 10
    mov dword ptr [0x6008], eax
2:  test ebx, ebx
    jnz 1b
3:

    # графика через BIOS (VBE): ищем режим 800×600, 32 бита на точку, с линейной видеопамятью
    mov di, 0x1000
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne видео_нет
    mov si, word ptr [0x100E]       # список режимов: смещение и сегмент
    mov ax, word ptr [0x1010]
    mov fs, ax
перебор_режимов:
    mov cx, word ptr fs:[si]
    cmp cx, 0xFFFF
    je видео_нет
    add si, 2
    push si
    mov di, 0x1200
    mov ax, 0x4F01
    int 0x10
    pop si
    cmp ax, 0x004F
    jne перебор_режимов
    mov ax, word ptr [0x1200]       # свойства режима: поддерживается, цветной, графика, линейная память
    and ax, 0x99
    cmp ax, 0x99
    jne перебор_режимов
    cmp word ptr [0x1212], 800
    jne перебор_режимов
    cmp word ptr [0x1214], 600
    jne перебор_режимов
    cmp byte ptr [0x1219], 32
    jne перебор_режимов
    mov bx, cx
    or bx, 0x4000                   # включить линейную видеопамять
    mov ax, 0x4F02
    int 0x10
    cmp ax, 0x004F
    jne видео_нет
    # сообщаем ядру, где экран (поля Multiboot: адрес, шаг строки, ширина, высота, глубина)
    mov dword ptr [0x6000], 0x1001
    mov eax, dword ptr [0x1228]
    mov dword ptr [0x6058], eax
    mov dword ptr [0x605C], 0
    movzx eax, word ptr [0x1210]
    mov dword ptr [0x6060], eax
    mov dword ptr [0x6064], 800
    mov dword ptr [0x6068], 600
    mov dword ptr [0x606C], 0x00010020
видео_нет:

    # читаем ядро кусками по 32 сектора
    mov word ptr [сегмент_чтения], 0x2000
    mov dword ptr [номер_сектора], ЯДРО_ПЕРВЫЙ_СЕКТОР
    mov ecx, ЯДРО_СЕКТОРОВ
4:  test ecx, ecx
    jz 6f
    mov ax, 32
    cmp ecx, 32
    jae 5f
    mov ax, cx
5:  mov word ptr [пакет + 2], ax
    mov bx, word ptr [сегмент_чтения]
    mov word ptr [пакет + 6], bx
    mov ebx, dword ptr [номер_сектора]
    mov dword ptr [пакет + 8], ebx
    push ax
    push ecx
    mov si, offset пакет
    mov dl, byte ptr [диск]
    mov ah, 0x42
    int 0x13
    pop ecx
    pop ax
    jc ошибка
    movzx eax, ax
    add dword ptr [номер_сектора], eax
    sub ecx, eax
    shl eax, 5                      # секторов * 32 = сдвиг сегмента (по 16 байт)
    add word ptr [сегмент_чтения], ax
    jmp 4b
6:

    cli
    lgdt [указатель_gdt]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:protected

ошибка:
    mov si, offset сообщение_ошибки
7:  lodsb
    test al, al
    jz 8f
    mov ah, 0x0E
    mov bx, 7
    int 0x10
    jmp 7b
8:  hlt
    jmp 8b

.code32
protected:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x7000
    cld
    cmp dword ptr [0x6058], 0       # если экран включён — рисуем сообщение нашим шрифтом (с кириллицей)
    je 9f
    mov edi, dword ptr [0x6058]     # фон
    mov edx, 600
11: mov ecx, 800
    mov eax, 0x00101820
    rep stosd
    mov eax, dword ptr [0x6060]
    sub eax, 3200
    add edi, eax
    dec edx
    jnz 11b
    mov esi, offset сообщение_загрузчика
    mov edi, dword ptr [0x6058]
    mov ebp, dword ptr [0x6060]
12: movzx eax, byte ptr [esi]
    cmp al, 255
    je 9f
    inc esi
    shl eax, 4
    add eax, offset sfera_font_8x16
    push edi
    mov ecx, 16
13: mov dl, byte ptr [eax]
    inc eax
    push edi
    mov bl, 8
14: test dl, 0x80
    jz 15f
    mov dword ptr [edi], 0x00DCE6F0
15: shl dl, 1
    add edi, 4
    dec bl
    jnz 14b
    pop edi
    add edi, ebp
    dec ecx
    jnz 13b
    pop edi
    add edi, 32
    jmp 12b
9:
# для отладки: -defsym ПАУЗА=1 останавливает загрузчик после вывода сообщения
.ifdef ПАУЗА
    cli
99: hlt
    jmp 99b
.endif
    mov esi, 0x20000                # копируем ядро на 1 МБ
    mov edi, 0x100000
    mov ecx, ЯДРО_ДВОЙНЫХ_СЛОВ
    rep movsd
    mov edi, ЯДРО_КОНЕЦ_ОБРАЗА      # обнуляем bss ядра
    mov ecx, BSS_ДВОЙНЫХ_СЛОВ
    xor eax, eax
    rep stosd
    mov eax, 0x2BADB002
    mov ebx, 0x6000
    mov ecx, ЯДРО_ВХОД
    jmp ecx

сообщение_загрузчика:
    .include "сообщение.inc"
.include "шрифт_8х16.s"
.section .text
.balign 8
gdt:
    .quad 0
    .quad 0x00CF9A000000FFFF        # 32-битный код, 4 ГБ
    .quad 0x00CF92000000FFFF        # 32-битные данные, 4 ГБ
указатель_gdt:
    .word указатель_gdt - gdt - 1
    .long gdt

диск:
    .byte 0
.balign 4
номер_сектора:
    .long 0
сегмент_чтения:
    .word 0
сообщение_ошибки:
    .asciz "Sfera: oshibka chteniya yadra\r\n"
.balign 4
пакет:
    .byte 0x10, 0
    .word 0
    .word 0                         # смещение
    .word 0                         # сегмент
    .quad 0
