# запуск_riscv64.s — стартовый код для RISC-V 64 (плата QEMU «virt»).
# Загрузка по адресу 0x80000000: ставим стек, включаем дробные числа,
# обнуляем .bss, вызываем main() (его делает компилятор Сферы), затем останавливаемся.

    .section .text.start,"ax"
    .global _start
_start:
    la      sp, sfera_stack_top
    li      t0, 0x2000              # mstatus.FS = 1: дробный сопроцессор включён
    csrs    mstatus, t0
    la      t0, sfera_bss_start
    la      t1, sfera_bss_end
1:  bgeu    t0, t1, 2f
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       1b
2:  la      t0, sfera_trap_entry
    csrw    mtvec, t0               # куда идти при прерывании
    li      t0, -1
    li      t1, 0x02004000          # mtimecmp: таймер пока ничего не просит
    sd      t0, 0(t1)
    li      t0, 0x80                # mie.MTIE: прерывания таймера разрешены
    csrs    mie, t0
    li      t0, 0x8                 # mstatus.MIE: прерывания включены
    csrs    mstatus, t0
    call    main
    li      t0, 0x100000            # тестовое устройство QEMU: выключить машину
    li      t1, 0x5555
    sw      t1, 0(t0)
3:  wfi
    j       3b

# Вход в прерывание: сохраняем всё, что может испортить функция на Сфере,
# вызываем sfera_trap() (её пишет программа; по умолчанию пустая) и возвращаемся.
    .balign 4
sfera_trap_entry:
    addi    sp, sp, -352
    sd      ra, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    sd      t2, 24(sp)
    sd      a0, 32(sp)
    sd      a1, 40(sp)
    sd      a2, 48(sp)
    sd      a3, 56(sp)
    sd      a4, 64(sp)
    sd      a5, 72(sp)
    sd      a6, 80(sp)
    sd      a7, 88(sp)
    sd      t3, 96(sp)
    sd      t4, 104(sp)
    sd      t5, 112(sp)
    sd      t6, 120(sp)
    fsd     ft0, 128(sp)
    fsd     ft1, 136(sp)
    fsd     ft2, 144(sp)
    fsd     ft3, 152(sp)
    fsd     ft4, 160(sp)
    fsd     ft5, 168(sp)
    fsd     ft6, 176(sp)
    fsd     ft7, 184(sp)
    fsd     fa0, 192(sp)
    fsd     fa1, 200(sp)
    fsd     fa2, 208(sp)
    fsd     fa3, 216(sp)
    fsd     fa4, 224(sp)
    fsd     fa5, 232(sp)
    fsd     fa6, 240(sp)
    fsd     fa7, 248(sp)
    fsd     ft8, 256(sp)
    fsd     ft9, 264(sp)
    fsd     ft10, 272(sp)
    fsd     ft11, 280(sp)
    call    sfera_trap
    ld      ra, 0(sp)
    ld      t0, 8(sp)
    ld      t1, 16(sp)
    ld      t2, 24(sp)
    ld      a0, 32(sp)
    ld      a1, 40(sp)
    ld      a2, 48(sp)
    ld      a3, 56(sp)
    ld      a4, 64(sp)
    ld      a5, 72(sp)
    ld      a6, 80(sp)
    ld      a7, 88(sp)
    ld      t3, 96(sp)
    ld      t4, 104(sp)
    ld      t5, 112(sp)
    ld      t6, 120(sp)
    fld     ft0, 128(sp)
    fld     ft1, 136(sp)
    fld     ft2, 144(sp)
    fld     ft3, 152(sp)
    fld     ft4, 160(sp)
    fld     ft5, 168(sp)
    fld     ft6, 176(sp)
    fld     ft7, 184(sp)
    fld     fa0, 192(sp)
    fld     fa1, 200(sp)
    fld     fa2, 208(sp)
    fld     fa3, 216(sp)
    fld     fa4, 224(sp)
    fld     fa5, 232(sp)
    fld     fa6, 240(sp)
    fld     fa7, 248(sp)
    fld     ft8, 256(sp)
    fld     ft9, 264(sp)
    fld     ft10, 272(sp)
    fld     ft11, 280(sp)
    addi    sp, sp, 352
    mret

    .weak   sfera_trap
sfera_trap:
    ret

# Куча для распределителя на Сфере (стандартная_библиотека/голое_железо.код).
    .text
    .global "sfera_куча_начало"
"sfera_куча_начало":
    la      a0, sfera_arena
    ret

    .global "sfera_куча_размер"
"sfera_куча_размер":
    li      a0, 1048576
    ret

    .section .bss
    .balign 16
sfera_arena:
    .skip 1048576
