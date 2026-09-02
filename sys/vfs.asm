; sys/vfs.asm - 内存虚拟文件系统（文件格式组件的存储层）
; 文件类型：0=raw 1=exe 2=batch 3=app-package 4=driver
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "vfs.inc"
global vfs_init, vfs_add_blob, vfs_find, vfs_delete, vfs_list_print, vfs_count

extern kmalloc
extern serial_printf
extern strcmp

section .data
global vfs_head
vfs_head: dq 0

section .text

vfs_init:
    mov qword [vfs_head], 0
    ret

; VFile *vfs_add_blob(name, type, data, size)
vfs_add_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; name
    mov r13d, esi                       ; type
    mov r14, rdx                        ; data
    mov r15d, ecx                       ; size
    ; 重名则更新
    mov rdi, r12
    call vfs_find
    test rax, rax
    jz .alloc
    mov [rax + VFile.type], r13d
    mov [rax + VFile.size], r15d
    mov [rax + VFile.data], r14
    jmp .done
.alloc:
    mov rdi, VFile_size
    call kmalloc
    test rax, rax
    jz .fail
    mov rbx, rax
    ; 复制名字
    lea rdi, [rbx + VFile.name]
    mov rsi, r12
    push rbx
    call vfs_cpyname
    pop rbx
    mov [rbx + VFile.type], r13d
    mov [rbx + VFile.size], r15d
    mov [rbx + VFile.data], r14
    ; 入链
    mov rax, [vfs_head]
    mov [rbx + VFile.next], rax
    mov [vfs_head], rbx
    mov rax, rbx
    jmp .done
.fail:
    xor rax, rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

vfs_cpyname:
    push rdi
    push rsi
.loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .loop
.done:
    pop rsi
    pop rdi
    ret

; VFile *vfs_find(name)
vfs_find:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [vfs_head]
.loop:
    test rbx, rbx
    jz .nf
    lea rsi, [rbx + VFile.name]
    mov rdi, r12
    push rbx
    call strcmp
    pop rbx
    test rax, rax
    jz .found
    mov rbx, [rbx + VFile.next]
    jmp .loop
.found:
    mov rax, rbx
    pop r12
    pop rbx
    ret
.nf:
    xor rax, rax
    pop r12
    pop rbx
    ret

; int vfs_delete(name)
vfs_delete:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [vfs_head]
    cmp rbx, 0
    je .nf
    lea rsi, [rbx + VFile.name]
    push rbx
    call strcmp
    pop rbx
    test rax, rax
    jnz .walk
    mov rax, [rbx + VFile.next]
    mov [vfs_head], rax
    mov rax, 1
    jmp .done
.walk:
    cmp qword [rbx + VFile.next], 0
    je .nf
    mov rax, [rbx + VFile.next]
    push rbx
    push rax
    lea rsi, [rax + VFile.name]
    mov rdi, r12
    call strcmp
    pop rax
    pop rbx
    test rax, rax
    jz .unlink
    mov rbx, [rbx + VFile.next]
    jmp .walk
.unlink:
    mov rcx, [rax + VFile.next]
    mov [rbx + VFile.next], rcx
    mov rax, 1
    jmp .done
.nf:
    xor rax, rax
.done:
    pop r12
    pop rbx
    ret

; void vfs_list_print()：列出全部文件
vfs_list_print:
    push rbx
    mov rbx, [vfs_head]
.loop:
    test rbx, rbx
    jz .done
    mov rdi, fmt_file
    lea rsi, [rbx + VFile.name]
    mov edx, [rbx + VFile.type]
    mov ecx, [rbx + VFile.size]
    push rbx
    call serial_printf
    pop rbx
    mov rbx, [rbx + VFile.next]
    jmp .loop
.done:
    pop rbx
    ret

; int vfs_count()
vfs_count:
    xor eax, eax
    mov rcx, [vfs_head]
.loop:
    test rcx, rcx
    jz .done
    inc eax
    mov rcx, [rcx + VFile.next]
    jmp .loop
.done:
    ret

section .rodata
fmt_file db "  [%s] type=%d size=%d", 13, 10, 0
