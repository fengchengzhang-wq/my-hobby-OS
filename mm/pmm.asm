; mm/pmm.asm - 物理内存管理器（位图分配器）
; 位图：bit=1 表示空闲；覆盖 0..4GB（128KB 位图）
; 分配使用 bsf 加速，hint 使连续分配接近 O(1)
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "bootinfo.inc"

global init_pmm, pmm_alloc, pmm_free, pmm_alloc_contig, pmm_get_stats
global pmm_alloc_zero

extern _kernel_phys_end

PM_BITMAP_BYTES equ (4 * 1024 * 1024 * 1024) / 4096 / 8   ; 128KB
PM_MAX_PAGES    equ (4 * 1024 * 1024 * 1024) / 4096
PM_LOW_RESERVE  equ 0x100000                              ; 保留低 1MB
PM_KERNEL_PHYS  equ 0x200000                              ; 内核起始物理地址

section .bss
align 16
pmm_bitmap: resb PM_BITMAP_BYTES

section .data
pmm_next_hint: dq 0
pmm_free_pages: dq 0
pmm_used_pages: dq 0

section .text

; void init_pmm(mem_map, entries)
init_pmm:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                        ; mem_map（先保存，防止被清零循环覆盖）
    mov r13, rsi                        ; 条目数

    ; 清零位图（初始全部视为已用）
    mov rdi, pmm_bitmap
    mov rcx, PM_BITMAP_BYTES / 8
    xor rax, rax
    rep stosq

    ; 释放可用内存区域（type == 1）：置位 = 空闲
    xor r14, r14
.free_loop:
    cmp r14, r13
    jae .free_done
    cmp dword [r12 + MemEntry.type], 1
    jne .next_entry
    mov rax, [r12 + MemEntry.base]
    mov rcx, [r12 + MemEntry.len]
    ; 跳过低 1MB 保留区
    mov rdx, PM_LOW_RESERVE
    cmp rax, rdx
    jae .no_clip
    sub rdx, rax
    cmp rcx, rdx
    jbe .next_entry
    sub rcx, rdx
    mov rax, PM_LOW_RESERVE
.no_clip:
    ; 释放 [base, base+len) 页：start = base>>12, end = (start*4096+len)>>12
    shr rax, 12
    mov rdi, rax                        ; start
    shl rax, 12                         ; start 字节地址
    add rax, rcx                        ; end 字节地址
    shr rax, 12                         ; end
    mov rsi, rax
    call pmm_set_range
    jmp .next_entry
.next_entry:
    add r12, 24
    inc r14
    jmp .free_loop
.free_done:
    ; 保留内核区域 [0x200000, _kernel_phys_end)：清位 = 已用
    mov rdi, PM_KERNEL_PHYS >> 12
    mov rax, _kernel_phys_end
    shr rax, 12
    mov rsi, rax
    call pmm_clr_range
    ; 页 0 强制保留（低 1MB 未释放时本就已用，双保险）
    mov rdi, 0
    call pmm_clr_bit
    ; 重新统计空闲页数
    call pmm_recount

    mov qword [pmm_next_hint], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- 位图原语 ----
; void pmm_set_bit(index)：置 1（空闲）
pmm_set_bit:
    mov rax, rdi
    shr rax, 6
    mov rdx, rdi
    and rdx, 63
    bts qword [pmm_bitmap + rax*8], rdx
    ret

; void pmm_clr_bit(index)：清 0（已用）
pmm_clr_bit:
    mov rax, rdi
    shr rax, 6
    mov rdx, rdi
    and rdx, 63
    btr qword [pmm_bitmap + rax*8], rdx
    ret

; void pmm_set_range(start, end)：页索引区间置 1
pmm_set_range:
    push rbx
.loop:
    cmp rdi, rsi
    jae .done
    push rdi
    push rsi
    call pmm_set_bit
    pop rsi
    pop rdi
    inc rdi
    jmp .loop
.done:
    pop rbx
    ret

; void pmm_clr_range(start, end)：页索引区间清 0
pmm_clr_range:
    push rbx
    mov rbx, rdi
.loop:
    cmp rbx, rsi
    jae .done
    mov rdi, rbx
    push rsi
    call pmm_clr_bit
    pop rsi
    inc rbx
    jmp .loop
.done:
    pop rbx
    ret

; ---- 分配 ----
; uint64 pmm_alloc() -> 物理地址，失败返回 0
pmm_alloc:
    push rbx
    push rcx
    mov rax, [pmm_next_hint]
    shr rax, 18                         ; hint 物理地址 -> 位图 qword 索引
    mov rcx, PM_BITMAP_BYTES / 8
.scan:
    cmp rax, rcx
    jae .wrap
    mov rdx, [pmm_bitmap + rax*8]
    test rdx, rdx
    jnz .found
    inc rax
    jmp .scan
.wrap:
    xor rax, rax
    mov rdx, [pmm_bitmap]
    test rdx, rdx
    jz .fail
.found:
    bsf rbx, rdx
    ; 页索引 = qword*64 + bit
    mov rdx, rax
    shl rdx, 6
    add rdx, rbx
    ; 清位
    mov rbx, rdx
    shr rbx, 6
    mov rcx, rdx
    and rcx, 63
    btr qword [pmm_bitmap + rbx*8], rcx
    ; 物理地址
    shl rdx, 12
    mov [pmm_next_hint], rdx
    dec qword [pmm_free_pages]
    inc qword [pmm_used_pages]
    mov rax, rdx
    pop rcx
    pop rbx
    ret
.fail:
    xor rax, rax
    pop rcx
    pop rbx
    ret

; void *pmm_alloc_zero()：分配并清零一页
pmm_alloc_zero:
    push rdi
    push rcx
    call pmm_alloc
    test rax, rax
    jz .done
    mov rdi, rax
    mov rcx, 512
    xor rax, rax
    rep stosq
.done:
    pop rcx
    pop rdi
    ret

; void pmm_free(addr)
pmm_free:
    mov rax, rdi
    shr rax, 12
    mov rdx, rax
    shr rdx, 6
    mov rcx, rax
    and rcx, 63
    bts qword [pmm_bitmap + rdx*8], rcx
    cmp [pmm_next_hint], rdi
    jbe .done
    mov [pmm_next_hint], rdi
.done:
    inc qword [pmm_free_pages]
    dec qword [pmm_used_pages]
    ret

; uint64 pmm_alloc_contig(pages) -> 起始物理地址，失败返回 0
pmm_alloc_contig:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; 需要的页数
    test r12, r12
    jz .fail
    mov r13, 0                          ; 当前扫描页
    xor r14, r14                        ; 当前连续长度
    mov r15, 0                          ; 连续段起点
.scan:
    cmp r13, PM_MAX_PAGES
    jae .fail
    ; 测试页 r13 是否空闲
    mov rax, r13
    shr rax, 6
    mov rdx, r13
    and rdx, 63
    bt qword [pmm_bitmap + rax*8], rdx
    jnc .used
    test r14, r14
    jnz .extend
    mov r15, r13
.extend:
    inc r14
    cmp r14, r12
    jae .claim
    jmp .next
.used:
    xor r14, r14
.next:
    inc r13
    jmp .scan
.claim:
    ; 清掉 r15..r15+r12 的位
    mov r13, 0
.clr_loop:
    cmp r13, r12
    jae .clr_done
    mov rax, r15
    add rax, r13
    push rdi
    push rsi
    mov rdi, rax
    call pmm_clr_bit
    pop rsi
    pop rdi
    inc r13
    jmp .clr_loop
.clr_done:
    mov rax, r15
    shl rax, 12
    sub qword [pmm_free_pages], r12
    add qword [pmm_used_pages], r12
    jmp .done
.fail:
    xor rax, rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; void pmm_recount()：重算空闲页数
pmm_recount:
    push rbx
    push rcx
    push rdx
    push r8
    xor rbx, rbx
    mov rcx, PM_BITMAP_BYTES / 8
    xor rdx, rdx
.loop:
    mov rax, [pmm_bitmap + rdx*8]
    test rax, rax
    jz .next
.count:
    test rax, rax
    jz .next
    bsf r8, rax
    inc rbx
    btr rax, r8
    jmp .count
.next:
    inc rdx
    cmp rdx, rcx
    jb .loop
    mov [pmm_free_pages], rbx
    mov rax, PM_MAX_PAGES
    sub rax, rbx
    mov [pmm_used_pages], rax
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; void pmm_get_stats(Stats*)：{total, free, used} 页数
pmm_get_stats:
    mov rax, PM_MAX_PAGES
    mov [rdi], rax
    mov rax, [pmm_free_pages]
    mov [rdi + 8], rax
    mov rax, [pmm_used_pages]
    mov [rdi + 16], rax
    ret
