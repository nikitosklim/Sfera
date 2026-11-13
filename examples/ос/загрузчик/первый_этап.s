# первый_этап.s — загрузочный сектор (512 байт) для компьютеров с обычным BIOS.
#
# BIOS читает первый сектор диска по адресу 0x7C00 и передаёт ему управление (dl — номер диска).
# Мы читаем с диска второй этап (сразу за этим сектором) по адресу 0x7E00 и переходим на него.
# Число секторов второго этапа подставляет сборочный скрипт (ЭТАП2_СЕКТОРОВ).

.intel_syntax noprefix
.code16
.section .text
.global _start
_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov byte ptr [диск], dl
    mov si, offset сообщение
    call печать
    mov si, offset пакет
    mov dl, byte ptr [диск]
    mov ah, 0x42                    # чтение секторов по номеру (расширение BIOS)
    int 0x13
    jc ошибка
    mov dl, byte ptr [диск]
    jmp 0x0000:0x7E00

ошибка:
    mov si, offset сообщение_ошибки
    call печать
1:  hlt
    jmp 1b

# Печать строки (si) средствами BIOS.
печать:
    lodsb
    test al, al
    jz 2f
    mov ah, 0x0E
    mov bx, 7
    int 0x10
    jmp печать
2:  ret

диск:
    .byte 0
сообщение:
    .asciz "Sfera: zagruzka...\r\n"
сообщение_ошибки:
    .asciz "Sfera: oshibka chteniya diska\r\n"

.balign 4
пакет:                              # пакет чтения диска
    .byte 0x10, 0
    .word ЭТАП2_СЕКТОРОВ
    .word 0x7E00
    .word 0
    .quad 1

.org 510
    .word 0xAA55
