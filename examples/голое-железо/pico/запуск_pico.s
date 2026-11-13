@ запуск_pico.s — стартовый код для Raspberry Pi Pico (RP2040, два ядра Cortex-M0+).
@ Программа целиком загружается в оперативную память (264 КБ) и выполняется оттуда, поэтому
@ не нужен второй загрузочный сектор flash-памяти (boot2). НА НАСТОЯЩЕЙ ПЛАТЕ НЕ ПРОВЕРЯЛОСЬ.

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
1:  wfi
    b       1b

@ Куча для распределителя на Сфере (128 КБ). «Целое» — 64 бита: младшая часть в r0, старшая в r1.
    .global "sfera_куча_начало"
    .thumb_func
"sfera_куча_начало":
    ldr     r0, =sfera_arena
    movs    r1, #0
    bx      lr
    .global "sfera_куча_размер"
    .thumb_func
"sfera_куча_размер":
    ldr     r0, =131072
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
    .space  131072
