; sys/pkg.asm - 软件安装/卸载/运行注册表
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "pkg.inc"
%include "vfs.inc"

global pkg_init, pkg_add, pkg_install, pkg_uninstall, pkg_run, pkg_find
global pkg_head

extern kmalloc
extern vfs_add_blob, vfs_find, vfs_delete
extern exec_run_file
extern batch_run
extern driver_register
extern serial_printf
extern strcmp
extern hello_exe_blob, hello_exe_size
extern demo_bat_blob, demo_bat_size

section .data
pkg_head: dq 0
pkg_idc: dd 1

; 外部队署应用启动函数
extern taskflow_launch
extern devmgr_launch
extern center_launch
extern console_launch

section .text

pkg_init:
    push rbp
    mov rbp, rsp
    ; 系统应用（预装）
    lea rdi, [n_taskflow]
    mov esi, PKG_SYS
    lea rdx, [taskflow_launch]
    call pkg_add
    lea rdi, [n_center]
    mov esi, PKG_SYS
    lea rdx, [center_launch]
    call pkg_add
    lea rdi, [n_devmgr]
    mov esi, PKG_SYS
    lea rdx, [devmgr_launch]
    call pkg_add
    lea rdi, [n_console]
    mov esi, PKG_SYS
    lea rdx, [console_launch]
    call pkg_add
    ; 可安装应用包
    lea rdi, [n_hello]
    mov esi, PKG_APP
    lea rdx, [v_hello]
    mov ecx, VFT_EXE
    mov r8, hello_exe_blob
    mov r9d, [hello_exe_size]
    push 0
    call pkg_add_file
    add rsp, 8
    lea rdi, [n_demo]
    mov esi, PKG_APP
    lea rdx, [v_demo]
    mov ecx, VFT_BATCH
    mov r8, demo_bat_blob
    mov r9d, [demo_bat_size]
    push 0
    call pkg_add_file
    add rsp, 8
    ; 默认安装演示包
    lea rdi, [n_hello]
    call pkg_install
    lea rdi, [n_demo]
    call pkg_install
    leave
    ret

; PkgEnt *pkg_add(name, kind, launch)：预装系统/驱动（无负载）
pkg_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov rdi, PkgEnt_size
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    call pkg_ent_init
    mov [rbx + PkgEnt.name], r12
    mov [rbx + PkgEnt.kind], r13d
    mov [rbx + PkgEnt.launch], r14
    mov dword [rbx + PkgEnt.inst], 1
    mov rax, rbx
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; PkgEnt *pkg_add_file(name, kind, vname, vtype, blob, size, launch_stack)
pkg_add_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; name
    mov r13d, esi                       ; kind
    mov r14, rdx                        ; vname
    mov r15d, ecx                       ; vtype
    mov rdi, PkgEnt_size
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    call pkg_ent_init
    mov [rbx + PkgEnt.name], r12
    mov [rbx + PkgEnt.kind], r13d
    mov [rbx + PkgEnt.vname], r14
    mov [rbx + PkgEnt.vtype], r15d
    mov [rbx + PkgEnt.blob], r8
    mov [rbx + PkgEnt.size], r9d
    mov rax, [rbp + 16]
    mov [rbx + PkgEnt.launch], rax
    mov dword [rbx + PkgEnt.inst], 0
    mov rax, rbx
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

pkg_ent_init:                           ; rbx = ent
    mov eax, [pkg_idc]
    mov [rbx + PkgEnt.id], eax
    inc dword [pkg_idc]
    mov qword [rbx + PkgEnt.launch], 0
    mov qword [rbx + PkgEnt.blob], 0
    mov dword [rbx + PkgEnt.size], 0
    mov dword [rbx + PkgEnt.inst], 0
    mov rax, [pkg_head]
    mov [rbx + PkgEnt.next], rax
    mov [pkg_head], rbx
    ret

; PkgEnt *pkg_find(name)
pkg_find:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [pkg_head]
.loop:
    test rbx, rbx
    jz .nf
    mov rsi, [rbx + PkgEnt.name]
    push rbx
    call strcmp
    pop rbx
    test rax, rax
    jz .found
    mov rbx, [rbx + PkgEnt.next]
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

; int pkg_install(name)：把负载写入 VFS 并标记已安装
pkg_install:
    push rbp
    mov rbp, rsp
    push rbx
    call pkg_find
    test rax, rax
    jz .bad
    mov rbx, rax
    cmp qword [rbx + PkgEnt.blob], 0
    je .native
    cmp dword [rbx + PkgEnt.inst], 0
    jne .ok
    mov rdi, [rbx + PkgEnt.vname]
    mov esi, [rbx + PkgEnt.vtype]
    mov rdx, [rbx + PkgEnt.blob]
    mov ecx, [rbx + PkgEnt.size]
    push rbx
    call vfs_add_blob
    pop rbx
    mov dword [rbx + PkgEnt.inst], 1
.ok:
    xor eax, eax
    jmp .done
.native:
    mov dword [rbx + PkgEnt.inst], 1
    xor eax, eax
    jmp .done
.bad:
    mov rax, -1
.done:
    pop rbx
    leave
    ret

; int pkg_uninstall(name)
pkg_uninstall:
    push rbp
    mov rbp, rsp
    push rbx
    call pkg_find
    test rax, rax
    jz .bad
    mov rbx, rax
    cmp qword [rbx + PkgEnt.blob], 0
    je .native
    mov rdi, [rbx + PkgEnt.vname]
    push rbx
    call vfs_delete
    pop rbx
.native:
    mov dword [rbx + PkgEnt.inst], 0
    xor eax, eax
    jmp .done
.bad:
    mov rax, -1
.done:
    pop rbx
    leave
    ret

; int pkg_run(name)
pkg_run:
    push rbp
    mov rbp, rsp
    push rbx
    call pkg_find
    test rax, rax
    jz .bad
    mov rbx, rax
    mov rax, [rbx + PkgEnt.launch]
    test rax, rax
    jz .byfile
    call rax
    xor eax, eax
    jmp .done
.byfile:
    cmp dword [rbx + PkgEnt.inst], 0
    je .bad
    mov eax, [rbx + PkgEnt.vtype]
    cmp eax, VFT_EXE
    jne .chk_bat
    mov rdi, [rbx + PkgEnt.vname]
    call exec_run_file
    jmp .done
.chk_bat:
    cmp eax, VFT_BATCH
    jne .bad
    ; 读取文件内容
    mov rdi, [rbx + PkgEnt.vname]
    push rbx
    call vfs_find
    pop rbx
    test rax, rax
    jz .bad
    mov rdi, [rax + VFile.data]
    call batch_run
    xor eax, eax
    jmp .done
.bad:
    mov rax, -1
.done:
    pop rbx
    leave
    ret

section .rodata
n_taskflow db "TaskFlow", 0
n_center   db "Software Center", 0
n_devmgr   db "Device Manager", 0
n_console  db "Console", 0
n_hello    db "HelloDemo", 0
n_demo     db "BatchDemo", 0
v_hello    db "hello.exe", 0
v_demo     db "demo.bat", 0
