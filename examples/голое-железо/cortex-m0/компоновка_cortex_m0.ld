/* компоновка_cortex_m7.ld — плата QEMU «mps2-an500»: код и константы с адреса 0, память для данных и стека с 0x20000000. */
ENTRY(sfera_reset)
SECTIONS
{
    . = 0x0;
    .vectors : { KEEP(*(.vectors)) }
    .text    : { *(.text .text.*) }
    .rodata  : { *(.rodata .rodata.*) }
    .ARM.exidx : { *(.ARM.exidx*) }
    . = 0x20000000;
    .data : { *(.data .data.*) }
    .bss  : { *(.bss .bss.*) *(COMMON) }
    . = ALIGN(8);
    . = . + 65536;
    sfera_stack_top = .;
}
