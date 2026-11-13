@ запуск_cortex_m7.s — стартовый код для ARM Cortex-M7 (плата QEMU «mps2-an500»).
@ Таблица векторов, включение дробного сопроцессора, вызов main() и выход из QEMU.
@ Ниже — маленькая «библиотека поддержки»: 64-битное деление и перевод дробных чисел,
@ которые процессор не умеет сам (у компилятора Сферы на 32-битных платах нет libgcc).

    .syntax unified
    .cpu cortex-m7
    .fpu fpv5-d16
    .thumb

    .section .vectors,"a"
    .word   sfera_stack_top
    .word   sfera_reset
    .rept   13
    .word   sfera_fault
    .endr
    .word   sfera_systick           @ прерывание системного таймера (SysTick)

    .text
    .thumb_func
sfera_fault:
    b       sfera_fault

@ Обработчик таймера по умолчанию; программа на Сфере может определить свою
@ функцию sfera_systick() — она заменит эту.
    .weak   sfera_systick
    .thumb_func
sfera_systick:
    bx      lr

    .thumb_func
    .global sfera_reset
sfera_reset:
    ldr     r0, =0xE000ED88         @ CPACR: разрешить сопроцессоры CP10/CP11
    ldr     r1, [r0]
    orr     r1, r1, #(0xF << 20)
    str     r1, [r0]
    dsb
    isb
    bl      main
    movs    r0, #0x20               @ SYS_EXIT_EXTENDED через «полухостинг» QEMU
    adr     r1, sfera_exit_block
    bkpt    0xAB
1:  wfi
    b       1b
    .balign 4
sfera_exit_block:
    .word   0x20026                 @ ADP_Stopped_ApplicationExit
    .word   0

@ Куча для распределителя на Сфере (стандартная_библиотека/голое_железо.код).
    .global "sfera_куча_начало"
    .thumb_func
"sfera_куча_начало":
    ldr     r0, =sfera_arena
    movs    r1, #0                  @ «целое» — 64 бита: старшая часть в r1
    bx      lr
    .global "sfera_куча_размер"
    .thumb_func
"sfera_куча_размер":
    ldr     r0, =524288
    movs    r1, #0
    bx      lr
    .ltorg

@ ---- поддержка ----
    .global __aeabi_unwind_cpp_pr0
    .thumb_func
__aeabi_unwind_cpp_pr0:
    bx      lr

@ беззнаковое деление 64 бит: делимое r1:r0, делитель r3:r2 -> частное r1:r0, остаток r3:r2
    .thumb_func
sfera_uldivmod:
    push    {r4-r9}
    movs    r4, #0
    movs    r5, #0
    movs    r6, #0
    movs    r7, #0
    mov     r12, #64
1:  lsls    r0, r0, #1
    adcs    r1, r1, r1
    adcs    r6, r6, r6
    adcs    r7, r7, r7
    subs    r8, r6, r2
    sbcs    r9, r7, r3
    itt     hs
    movhs   r6, r8
    movhs   r7, r9
    adcs    r4, r4, r4
    adcs    r5, r5, r5
    subs    r12, r12, #1
    bne     1b
    mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    mov     r3, r7
    pop     {r4-r9}
    bx      lr

    .macro  negate lo, hi
    rsbs    \lo, \lo, #0
    mvn     \hi, \hi
    adc     \hi, \hi, #0
    .endm

    .global __udivdi3
    .thumb_func
__udivdi3:
    b       sfera_uldivmod

    .global __umoddi3
    .thumb_func
__umoddi3:
    push    {lr}
    bl      sfera_uldivmod
    mov     r0, r2
    mov     r1, r3
    pop     {pc}

    .global __divdi3
    .thumb_func
__divdi3:
    push    {r4, lr}
    eor     r4, r1, r3
    cmp     r1, #0
    bge     1f
    negate  r0, r1
1:  cmp     r3, #0
    bge     2f
    negate  r2, r3
2:  bl      sfera_uldivmod
    cmp     r4, #0
    bge     3f
    negate  r0, r1
3:  pop     {r4, pc}

    .global __moddi3
    .thumb_func
__moddi3:
    push    {r4, lr}
    mov     r4, r1
    cmp     r1, #0
    bge     1f
    negate  r0, r1
1:  cmp     r3, #0
    bge     2f
    negate  r2, r3
2:  bl      sfera_uldivmod
    mov     r0, r2
    mov     r1, r3
    cmp     r4, #0
    bge     3f
    negate  r0, r1
3:  pop     {r4, pc}

@ целое 64 бита (r1:r0) -> double (r1:r0)
    .global __floatdidf
    .thumb_func
__floatdidf:
    vmov    s0, r1
    vcvt.f64.s32 d1, s0
    vmov    s0, r0
    vcvt.f64.u32 d2, s0
    mov     r2, #0x80000000
    vmov    s0, r2
    vcvt.f64.u32 d3, s0
    vadd.f64 d3, d3, d3             @ 2^32
    vmla.f64 d2, d1, d3
    vmov    r0, r1, d2
    bx      lr

@ double (r1:r0) -> целое 64 бита (r1:r0), с отбрасыванием дробной части
    .global __fixdfdi
    .thumb_func
__fixdfdi:
    mov     r3, r1
    vmov    d0, r0, r1
    vabs.f64 d1, d0
    mov     r2, #0x80000000
    vmov    s0, r2
    vcvt.f64.u32 d3, s0
    vadd.f64 d3, d3, d3             @ 2^32
    vdiv.f64 d4, d1, d3
    vcvt.u32.f64 s10, d4            @ старшая часть
    vcvt.f64.u32 d5, s10
    vmls.f64 d1, d5, d3
    vcvt.u32.f64 s12, d1            @ младшая часть
    vmov    r0, s12
    vmov    r1, s10
    cmp     r3, #0
    bge     1f
    negate  r0, r1
1:  bx      lr

    .bss
    .balign 16
sfera_arena:
    .space  524288
