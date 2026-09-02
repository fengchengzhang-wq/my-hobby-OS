; mm/heap.asm - 内核堆分配器（首适应 + 地址排序空闲链表 + 双向合并）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global init_heap, kmalloc, kfree

extern pmm_alloc_contig
extern panic

HEAP_PAGES  equ 1024                    ; 4MB 堆
BLOCK_HDR   equ 32
BLOCK_MAGIC equ 0x4C4C414B              ; 'KALL'

struc Block
    .size  resq 1                       ; 可用区大小（不含头部）
    .magic resq 1
    .prev  resq 1                       ; 空闲链表前驱
    .next  resq 1                       ; 空闲链表后继
endstruc

section .data
heap_base: dq 0
heap_end:  dq 0
global free_list
free_list: dq 0                         ; 按地址升序的空闲链表


section .text

init_heap:
    sub rsp, 8                          ; 保证调用 pmm_alloc_contig 时 rsp%16==0
    mov rdi, HEAP_PAGES
    call pmm_alloc_contig
    test rax, rax
    jz .fail
    mov [heap_base], rax
    lea rbx, [rax + HEAP_PAGES * 4096]
    mov [heap_end], rbx
    ; 初始化一个大空闲块
    mov [rax + Block.size], rbx
    sub qword [rax + Block.size], rax
    sub qword [rax + Block.size], BLOCK_HDR
    mov qword [rax + Block.magic], BLOCK_MAGIC
    mov qword [rax + Block.prev], 0
    mov qword [rax + Block.next], 0
    mov [free_list], rax
    add rsp, 8
    ret
.fail:
    mov rdi, msg_heap_oom
    call panic

; void *kmalloc(size)：16 字节对齐
kmalloc:
    add rdi, 15
    and rdi, ~15
    cmp rdi, 16
    jae .size_ok
    mov rdi, 16
.size_ok:
    push rbx
    push r12
    push r13
    mov rbx, [free_list]                ; 当前块
    xor r12, r12                        ; 前驱
.search:
    test rbx, rbx
    jz .fail
    cmp [rbx + Block.size], rdi
    jae .found
    mov r12, rbx
    mov rbx, [rbx + Block.next]
    jmp .search
.found:
    ; 剩余空间是否足够拆出新块
    mov rax, [rbx + Block.size]
    sub rax, rdi
    cmp rax, BLOCK_HDR + 16
    jb .no_split
    ; 拆分：新空闲块 = rbx + HDR + size
    lea r13, [rbx + BLOCK_HDR + rdi]
    mov [r13 + Block.size], rax
    sub qword [r13 + Block.size], BLOCK_HDR
    mov qword [r13 + Block.magic], BLOCK_MAGIC
    mov rdx, [rbx + Block.next]
    mov [r13 + Block.next], rdx
    mov [r13 + Block.prev], r12
    test rdx, rdx
    jz .no_next
    mov [rdx + Block.prev], r13
.no_next:
    test r12, r12
    jz .no_prev
    mov [r12 + Block.next], r13
    jmp .splitted
.no_prev:
    mov [free_list], r13
.splitted:
    mov [rbx + Block.size], rdi
    mov qword [rbx + Block.magic], BLOCK_MAGIC
    mov qword [rbx + Block.prev], 0
    mov qword [rbx + Block.next], 0
    lea rax, [rbx + BLOCK_HDR]
    jmp .done
.no_split:
    ; 整块取出
    mov rdx, [rbx + Block.next]
    test r12, r12
    jz .first
    mov [r12 + Block.next], rdx
    jmp .unlinked
.first:
    mov [free_list], rdx
.unlinked:
    test rdx, rdx
    jz .no_n2
    mov [rdx + Block.prev], r12
.no_n2:
    mov qword [rbx + Block.prev], 0
    mov qword [rbx + Block.next], 0
    lea rax, [rbx + BLOCK_HDR]
.done:
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; void kfree(ptr)
kfree:
    test rdi, rdi
    jz .done
    sub rdi, BLOCK_HDR
    ; 校验 magic
    cmp qword [rdi + Block.magic], BLOCK_MAGIC
    je .magic_ok
    mov rdi, msg_bad_free
    call panic
.magic_ok:
    mov qword [rdi + Block.magic], 0
    push rbx
    push r12
    push r13
    ; 按地址插入空闲链表
    mov rbx, [free_list]
    xor r12, r12                        ; prev
.insert:
    test rbx, rbx
    jz .inserted
    cmp rdi, rbx
    jb .inserted
    mov r12, rbx
    mov rbx, [rbx + Block.next]
    jmp .insert
.inserted:
    mov [rdi + Block.prev], r12
    mov [rdi + Block.next], rbx
    test rbx, rbx
    jz .no_next
    mov [rbx + Block.prev], rdi
.no_next:
    test r12, r12
    jz .no_prev
    mov [r12 + Block.next], rdi
    jmp .linked
.no_prev:
    mov [free_list], rdi
.linked:
    ; ---- 与后继合并 ----
.coalesce_next:
    mov rbx, [rdi + Block.next]
    test rbx, rbx
    jz .coalesce_prev
    ; 若 rdi 块末尾 == rbx 块起始
    mov rax, rdi
    add rax, BLOCK_HDR
    add rax, [rdi + Block.size]
    cmp rax, rbx
    jne .coalesce_prev
    ; 合并
    mov rdx, [rbx + Block.size]
    add rdx, BLOCK_HDR
    add [rdi + Block.size], rdx
    mov rdx, [rbx + Block.next]
    mov [rdi + Block.next], rdx
    test rdx, rdx
    jz .coalesce_prev
    mov [rdx + Block.prev], rdi
    jmp .coalesce_prev
.coalesce_prev:
    mov r12, [rdi + Block.prev]
    test r12, r12
    jz .done_coalesce
    mov rax, r12
    add rax, BLOCK_HDR
    add rax, [r12 + Block.size]
    cmp rax, rdi
    jne .done_coalesce
    ; 前驱吸收当前块
    mov rdx, [rdi + Block.size]
    add rdx, BLOCK_HDR
    add [r12 + Block.size], rdx
    mov rdx, [rdi + Block.next]
    mov [r12 + Block.next], rdx
    test rdx, rdx
    jz .done_coalesce
    mov [rdx + Block.prev], r12
.done_coalesce:
    pop r13
    pop r12
    pop rbx
.done:
    ret

section .rodata
msg_heap_oom  db "PANIC: heap init out of memory", 0
msg_bad_free  db "PANIC: kfree invalid pointer (double free?)", 0
