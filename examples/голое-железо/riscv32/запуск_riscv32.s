# запуск_riscv32.s — стартовый код для RISC-V 32 (rv32imac, без сопроцессора; плата QEMU «virt»).
# Ставим стек, обнуляем .bss, вызываем main() (его делает компилятор Сферы), выключаем машину.
# Дробные числа считает библиотека дробные_программно (на самой Сфере).

    .section .text.start,"ax"
    .global _start
_start:
    la      sp, sfera_stack_top
    la      t0, sfera_bss_start
    la      t1, sfera_bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    main
    li      t0, 0x100000            # тестовое устройство QEMU: выключить машину
    li      t1, 0x5555
    sw      t1, 0(t0)
3:  wfi
    j       3b

# Куча для распределителя на Сфере. Результат типа «целое» (64 бита) на 32-битном процессоре
# возвращается парой регистров: младшая часть в a0, старшая в a1.
    .text
    .global "sfera_куча_начало"
"sfera_куча_начало":
    la      a0, sfera_arena
    li      a1, 0
    ret

    .global "sfera_куча_размер"
"sfera_куча_размер":
    li      a0, 1048576
    li      a1, 0
    ret

    .section .bss
    .balign 16
sfera_arena:
    .skip 1048576
