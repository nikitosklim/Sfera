# старт.s — запуск программы пользователя (кольцо 3): вызывает главную() и завершает программу системным вызовом «выход».
# Системный вызов — int 0x80: rax — номер, rdi, rsi, rdx — параметры.
.intel_syntax noprefix
.section .text.start,"ax"
.global _start
_start:
    call main
    mov rdi, rax
    mov rax, 2                  # выход(код)
    int 0x80
1:  jmp 1b

# сисвызов(номер, а, б): целое — обёртка над int 0x80
.section .text
.global "sfera_сисвызов"
"sfera_сисвызов":
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    int 0x80
    ret

.section .note.GNU-stack,"",@progbits
