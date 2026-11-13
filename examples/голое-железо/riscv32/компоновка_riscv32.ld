/* компоновка_riscv64.ld — размещение программы для платы QEMU «virt» (память с 0x80000000). */
ENTRY(_start)
SECTIONS
{
    . = 0x80000000;
    .text   : { *(.text.start) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) }
    .data   : { *(.data .data.*) *(.sdata .sdata.*) }
    . = ALIGN(16);
    sfera_bss_start = .;
    .bss    : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) }
    . = ALIGN(16);
    sfera_bss_end = .;
    . = . + 65536;
    . = ALIGN(16);
    sfera_stack_top = .;
}
