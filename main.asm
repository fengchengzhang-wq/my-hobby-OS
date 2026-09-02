; main.asm - 内核主入口：子系统初始化顺序 + 系统报告 + 进入 GUI 主循环
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "bootinfo.inc"

global main

extern init_serial
extern load_gdt_tss
extern init_idt, init_pic
extern init_pmm, init_vmm, init_heap
extern init_framebuffer, init_keyboard, init_mouse, init_timer
extern init_rtc, init_pci, init_ata
extern init_speaker
extern kapi_init, init_syscall
extern drvreg_init
extern vfs_init, pkg_init, console_clear
extern wm_init, wm_run
extern boot_info
extern serial_printf, serial_write_string, serial_newline
extern pmm_get_stats
extern fb_width, fb_height, fb_ready, fb_addr, fb_pitch

section .data
banner db "MyOS 0.9.0 [x86_64 pure-assembly]", 13, 10, 0
memline db "Memory: total=%d KB free=%d KB used=%d KB", 13, 10, 0
fbfmt  db "Framebuffer: %dx%dx%d pitch=%d addr=%x", 13, 10, 0
fbnone db "Framebuffer: none (static fallback)", 13, 10, 0
ready  db "All subsystems initialized. Starting GUI...", 13, 10, 0

section .bss
mem_stats: resq 3

section .text
main:
    ; ---- 1. 串口（最早，用于调试） ----
    call init_serial
    lea rdi, [banner]
    call serial_write_string

    ; ---- 2. GDT + TSS ----
    call load_gdt_tss

    ; ---- 3. 中断 ----
    call init_idt
    call init_pic

    ; ---- 4. 内存管理 ----
    mov rdi, [boot_info + BootInfo.mem_map]
    mov rsi, [boot_info + BootInfo.mem_entries]
    call init_pmm
    call init_vmm
    call init_heap

    ; ---- 5. 设备驱动 ----
    call init_framebuffer
    call init_keyboard
    call init_mouse
    call init_timer
    call init_rtc
    call init_pci
    call init_ata
    call init_speaker

    ; ---- 6. 扩展 API ----
    call kapi_init
    call init_syscall

    ; ---- 7. 系统报告 ----
    call print_system_report
    call drvreg_init
    ; 系统服务：VFS / 控制台 / 软件包注册表
    call vfs_init
    call console_clear
    call pkg_init

    ; ---- 8. GUI ----
    lea rdi, [ready]
    call serial_write_string
    call wm_init
    sti
    call wm_run

    cli
    hlt

print_system_report:
    push rbp
    mov rbp, rsp
    ; 内存统计
    lea rdi, [mem_stats]
    call pmm_get_stats
    mov rdi, memline
    mov rsi, [mem_stats]
    shl rsi, 2                          ; 页 -> KB
    mov rdx, [mem_stats + 8]
    shl rdx, 2
    mov rcx, [mem_stats + 16]
    shl rcx, 2
    call serial_printf
    ; 帧缓冲
    cmp dword [fb_ready], 0
    je .no_fb
    mov rdi, fbfmt
    mov esi, [fb_width]
    mov edx, [fb_height]
    mov ecx, 32
    mov r8d, [fb_pitch]
    mov r9, [fb_addr]
    call serial_printf
    jmp .done
.no_fb:
    lea rdi, [fbnone]
    call serial_write_string
.done:
    leave
    ret
