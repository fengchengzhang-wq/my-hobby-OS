; mm/vmm.asm - 虚拟内存管理器（4 级页表：PML4->PDPT->PD->PT）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global init_vmm, vmm_map, vmm_unmap

extern pmm_alloc
extern pmm_alloc_zero

section .text

init_vmm:
    ret

; void vmm_zero_page(page)
vmm_zero_page:
    push rdi
    push rcx
    mov rcx, 512
    xor rax, rax
    rep stosq
    pop rcx
    pop rdi
    ret

; int vmm_map(virt, phys, size)：映射 size 字节（4KB 页），成功 0，失败 -1
vmm_map:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    test rdi, 0xFFF
    jnz .error
    test rsi, 0xFFF
    jnz .error

    mov r12, rdx                        ; 页数
    add r12, 0xFFF
    shr r12, 12
    test r12, r12
    jz .ok

    mov r13, cr3
    mov r8, rdi                         ; 当前虚拟地址
    mov r9, rsi                         ; 当前物理地址

.page_loop:
    ; ---- 各级索引 ----
    mov rax, r8
    shr rax, 39
    and rax, 0x1FF
    mov r10, rax                        ; PML4 索引
    mov rax, r8
    shr rax, 30
    and rax, 0x1FF
    mov r11, rax                        ; PDPT 索引
    mov rax, r8
    shr rax, 21
    and rax, 0x1FF
    mov r14, rax                        ; PD 索引
    mov rax, r8
    shr rax, 12
    and rax, 0x1FF
    mov r15, rax                        ; PT 索引

    ; ---- PML4 ----
    lea rbx, [r13 + r10*8]
    mov rdx, [rbx]
    test rdx, 1
    jnz .l1_ok
    call pmm_alloc_zero
    test rax, rax
    jz .error
    or rax, 3
    mov [rbx], rax
    mov rdx, rax
.l1_ok:
    test rdx, 1 << 7
    jnz .huge_error
    and rdx, ~0xFFF

    ; ---- PDPT ----
    lea rbx, [rdx + r11*8]
    mov rcx, [rbx]
    test rcx, 1
    jnz .l2_ok
    call pmm_alloc_zero
    test rax, rax
    jz .error
    or rax, 3
    mov [rbx], rax
    mov rcx, rax
.l2_ok:
    test rcx, 1 << 7
    jnz .huge_error
    and rcx, ~0xFFF

    ; ---- PD ----
    lea rbx, [rcx + r14*8]
    mov rdx, [rbx]
    test rdx, 1
    jnz .l3_ok
    call pmm_alloc_zero
    test rax, rax
    jz .error
    or rax, 3
    mov [rbx], rax
    mov rdx, rax
.l3_ok:
    test rdx, 1 << 7
    jnz .huge_error
    and rdx, ~0xFFF

    ; ---- PT 表项 ----
    lea rbx, [rdx + r15*8]
    mov rax, r9
    or rax, 3                           ; Present | Write
    mov [rbx], rax

    add r8, 0x1000
    add r9, 0x1000
    dec r12
    jnz .page_loop

    ; 刷新 TLB
    mov rax, cr3
    mov cr3, rax
.ok:
    xor rax, rax
    jmp .done
.huge_error:
.error:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int vmm_unmap(virt, size)：解除映射（不释放页表页）
vmm_unmap:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    add r12, 0xFFF
    shr r12, 12
    test r12, r12
    jz .ok
    mov r13, cr3
    mov r8, rdi

.page_loop:
    mov rax, r8
    shr rax, 39
    and rax, 0x1FF
    mov r10, rax
    mov rax, r8
    shr rax, 30
    and rax, 0x1FF
    mov r11, rax
    mov rax, r8
    shr rax, 21
    and rax, 0x1FF
    mov r14, rax
    mov rax, r8
    shr rax, 12
    and rax, 0x1FF
    mov r15, rax

    mov rdx, [r13 + r10*8]
    test rdx, 1
    jz .next
    and rdx, ~0xFFF
    mov rcx, [rdx + r11*8]
    test rcx, 1
    jz .next
    and rcx, ~0xFFF
    mov rdx, [rcx + r14*8]
    test rdx, 1
    jz .next
    and rdx, ~0xFFF
    mov qword [rdx + r15*8], 0
.next:
    add r8, 0x1000
    dec r12
    jnz .page_loop
    mov rax, cr3
    mov cr3, rax
.ok:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

