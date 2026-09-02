; sys/exec.asm - MyOS 可执行文件格式（.exe）与加载器
; 格式（二进制小端）：
;   0: magic "MYOSX1\0\0"
;   8: entry = 相对代码起始的偏移(u32)；加载器把 52 字节头后的
;      代码拷到新堆块并调用 堆块+entry（常规负载 entry=0）
;   12: 代码长度(u32)；拷贝区间 52..52+csize。负载的字符串必须
;       内联在代码区内，避免 [rel] 寻址指向未拷贝区域
;   16: 保留(u32)
;   20: 名称[32]
;   52+: 代码
; 入口 ABI：entry(rdi = print_fn)  打印到内核控制台；返回退出码
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "vfs.inc"

global exec_run_file, exec_run_blob

extern vfs_find
extern kmalloc, kfree
extern console_printf_fn

struc ExeHdr
    .magic resq 1
    .entry resd 1
    .csize resd 1
    .rsvd  resd 1
    .name  resb 32
endstruc

section .text

; int exec_run_file(name)：从 VFS 加载并运行
exec_run_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi
    mov rdi, r12
    call vfs_find
    test rax, rax
    jz .nf
    mov rbx, rax
    mov rdi, [rax + VFile.data]
    call exec_run_blob
    jmp .done
.nf:
    mov rax, -1
.done:
    pop r12
    pop rbx
    leave
    ret

; int exec_run_blob(code)
exec_run_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12, rdi
    ; 校验 magic（8 字节 "MYOSX1\0\0"）
    mov rax, [r12 + ExeHdr.magic]
    mov rdx, 0x3158534F594D
    cmp rax, rdx
    jne .bad
    mov r13d, [r12 + ExeHdr.csize]
    test r13d, r13d
    jz .bad
    ; 分配并拷贝代码
    mov edi, r13d
    call kmalloc
    test rax, rax
    jz .bad
    mov rbx, rax
    lea rsi, [r12 + ExeHdr_size]
    mov rdi, rbx
    mov ecx, r13d
    rep movsb
    ; 调用入口（使用当前栈；演示代码需克制栈使用）
    mov eax, [r12 + ExeHdr.entry]
    lea r13, [rbx + rax]
    mov rdi, console_printf_fn
    call r13
    mov r12, rax                        ; 返回码
    mov rdi, rbx
    call kfree
    mov rax, r12
    jmp .done
.bad:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret
