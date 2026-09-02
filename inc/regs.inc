; inc/regs.inc - 中断保存的寄存器帧布局（isr.asm / panic.asm 共用）

struc RegFrame
    .r15    resq 1
    .r14    resq 1
    .r13    resq 1
    .r12    resq 1
    .r11    resq 1
    .r10    resq 1
    .r9     resq 1
    .r8     resq 1
    .rbp    resq 1
    .rdi    resq 1
    .rsi    resq 1
    .rdx    resq 1
    .rcx    resq 1
    .rbx    resq 1
    .rax    resq 1
    .vec    resq 1
    .err    resq 1
    .rip    resq 1
    .cs     resq 1
    .rflags resq 1
    .rsp    resq 1
    .ss     resq 1
endstruc

