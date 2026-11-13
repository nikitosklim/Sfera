/* Программа пользователя: виртуальные адреса 0x40400000…0x407FFFFF (кадры и страницы выдаёт ядро при запуске). */
ENTRY(_start)
SECTIONS
{
    . = 0x40400000;
    .text : { *(.text.start) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) *(.bss .bss.*) *(COMMON) }
}
