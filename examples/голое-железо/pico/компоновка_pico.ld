/* компоновка_pico.ld — RP2040: всё в оперативной памяти (SRAM, 0x20000000…0x20040000), таблица векторов в начале. */
ENTRY(sfera_reset)
SECTIONS
{
    . = 0x20000000;
    .vectors : { KEEP(*(.vectors)) }
    .text    : { *(.text .text.*) }
    .rodata  : { *(.rodata .rodata.*) }
    .ARM.exidx : { *(.ARM.exidx*) }
    .data : { *(.data .data.*) }
    .bss  : { *(.bss .bss.*) *(COMMON) }
    . = ALIGN(8);
    /* стек — в самом конце памяти, растёт вниз */
    sfera_stack_top = 0x20040000;
}
