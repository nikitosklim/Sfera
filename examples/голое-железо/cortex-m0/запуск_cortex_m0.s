@ запуск_cortex_m0.s — стартовый код для ARM Cortex-M0/M0+ (набор команд ARMv6-M, без сопроцессора и без деления).
@ Проверяется в QEMU на плате mps2-an385 (ядро Cortex-M3, оно выполняет тот же код). Для настоящей платы
@ (Raspberry Pi Pico и др.) нужны свой запуск и своя «плата» — см. README.
@ Дробные числа и 64-битные целые считает библиотека дробные_программно (на самой Сфере).

    .syntax unified
    .cpu cortex-m0plus
    .thumb

    .section .vectors,"a"
    .word   sfera_stack_top
    .word   sfera_reset
    .rept   14
    .word   sfera_fault
    .endr

    .text
    .thumb_func
sfera_fault:
    b       sfera_fault

    .global sfera_reset
    .thumb_func
sfera_reset:
    bl      main
    movs    r0, #0x20               @ SYS_EXIT_EXTENDED через «полухостинг» QEMU
    adr     r1, sfera_exit_block
    bkpt    0xAB
1:  b       1b
    .balign 4
sfera_exit_block:
    .word   0x20026
    .word   0

@ Куча для распределителя на Сфере. «Целое» — 64 бита: младшая часть в r0, старшая в r1.
    .global "sfera_куча_начало"
    .thumb_func
"sfera_куча_начало":
    ldr     r0, =sfera_arena
    movs    r1, #0
    bx      lr
    .global "sfera_куча_размер"
    .thumb_func
"sfera_куча_размер":
    ldr     r0, =262144
    movs    r1, #0
    bx      lr
    .ltorg

    .global __aeabi_unwind_cpp_pr0
    .thumb_func
__aeabi_unwind_cpp_pr0:
    bx      lr

    .bss
    .balign 16
sfera_arena:
    .space  262144
