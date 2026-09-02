; drivers/pci.asm - PCI 配置空间访问 + 总线枚举
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "driver.inc"

global init_pci, pci_read_config, pci_find, pci_print_all
global pci_find_vga_fb
global pci_devices, pci_device_count

extern driver_register
extern serial_printf

PCI_CONFIG_ADDR equ 0xCF8
PCI_CONFIG_DATA equ 0xCFC
PCI_MAX_DEVICES equ 64

struc PciDevice
    .bus      resd 1
    .dev      resd 1
    .func     resd 1
    .vendor   resd 1
    .device   resd 1
    .class    resd 1
    .subclass resd 1
    .progif   resd 1
    .header   resd 1
endstruc

section .bss
align 16
pci_devices: resb PCI_MAX_DEVICES * PciDevice_size
pci_device_count: resd 1
pci_ident_buf: resb 512

section .data
global pci_driver
pci_driver:
    istruc Driver
        at Driver.name,  dq pci_name
        at Driver.kind,  dd DRV_KIND_BUS
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_pci
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
pci_name db "pci", 0
fmt_pci  db "PCI %x:%x.%x vendor=%x dev=%x class=%x%x progif=%x", 13, 10, 0

section .text

init_pci:
    call pci_scan
    call pci_print_all
    lea rdi, [pci_driver]
    call driver_register
    ret

; uint32 pci_read_config(bus, dev, func, reg)
pci_read_config:
    mov eax, 0x80000000
    shl rdi, 16
    or eax, edi
    shl rsi, 11
    or eax, esi
    shl rdx, 8
    or eax, edx
    and ecx, 0xFC
    or eax, ecx
    mov dx, PCI_CONFIG_ADDR
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in eax, dx
    ret

; void pci_scan()
pci_scan:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [pci_device_count], 0
    mov r14d, 0                         ; bus
.bus_loop:
    mov r15d, 0                         ; dev
.dev_loop:
    cmp r15d, 32
    jae .dev_done
    mov r12d, 0                         ; func
.func_loop:
    cmp r12d, 8
    jae .func_done
    ; 读取 vendor/device
    mov edi, r14d
    mov esi, r15d
    mov edx, r12d
    mov ecx, 0
    call pci_read_config
    mov ebx, eax                        ; vendor/device dword
    movzx eax, ax
    cmp eax, 0xFFFF
    je .no_device
    ; 记录设备
    mov eax, [pci_device_count]
    cmp eax, PCI_MAX_DEVICES
    jae .func_done
    imul rax, PciDevice_size
    lea r13, [pci_devices + rax]
    mov [r13 + PciDevice.bus], r14d
    mov [r13 + PciDevice.dev], r15d
    mov [r13 + PciDevice.func], r12d
    movzx eax, bx
    mov [r13 + PciDevice.vendor], eax
    shr ebx, 16
    mov [r13 + PciDevice.device], ebx
    ; class
    mov edi, r14d
    mov esi, r15d
    mov edx, r12d
    mov ecx, 8
    call pci_read_config
    mov ebx, eax
    mov eax, ebx
    shr eax, 24
    mov [r13 + PciDevice.class], eax
    mov eax, ebx
    shr eax, 16
    and eax, 0xFF
    mov [r13 + PciDevice.subclass], eax
    mov eax, ebx
    shr eax, 8
    and eax, 0xFF
    mov [r13 + PciDevice.progif], eax
    mov eax, ebx
    and eax, 0xFF
    mov [r13 + PciDevice.header], eax
    inc dword [pci_device_count]
    ; 若是多功能设备，继续扫描其余 func；否则只扫 func0
    test eax, 0x80
    jnz .next_func
    jmp .func_done
.no_device:
    jmp .func_done
.next_func:
    inc r12d
    jmp .func_loop
.func_done:
    inc r15d
    jmp .dev_loop
.dev_done:
    inc r14d
    cmp r14d, 2                         ; 扫描 bus 0-1（QEMU 典型布局）
    jb .bus_loop
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int pci_find(class, subclass, vendor=0任意)：返回设备指针或 0
pci_find:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov ebx, [pci_device_count]
    xor r15d, r15d
.loop:
    cmp r15d, ebx
    jae .notfound
    mov rax, r15
    imul rax, PciDevice_size
    lea rcx, [pci_devices + rax]
    cmp [rcx + PciDevice.class], r12d
    jne .next
    cmp [rcx + PciDevice.subclass], r13d
    jne .next
    test r14d, r14d
    jz .found
    cmp [rcx + PciDevice.vendor], r14d
    jne .next
.found:
    mov rax, rcx
    jmp .done
.next:
    inc r15d
    jmp .loop
.notfound:
    xor rax, rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; void pci_print_all()
pci_print_all:
    push rbx
    push r12
    push r13
    mov ebx, [pci_device_count]
    xor r12d, r12d
.loop:
    cmp r12d, ebx
    jae .done
    mov rax, r12
    imul rax, PciDevice_size
    lea r13, [pci_devices + rax]        ; 设备基址（r13 跨调用保留）
    mov rdi, fmt_pci
    mov esi, [r13 + PciDevice.bus]
    mov edx, [r13 + PciDevice.dev]
    mov ecx, [r13 + PciDevice.func]
    mov r8d, [r13 + PciDevice.vendor]
    mov r9d, [r13 + PciDevice.device]
    ; 第 7+ 个参数走栈：class/subclass/progif
    push qword [r13 + PciDevice.progif]
    push qword [r13 + PciDevice.subclass]
    push qword [r13 + PciDevice.class]
    call serial_printf
    add rsp, 24
    inc r12d
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

; uint64 pci_find_vga_fb()：返回首个 VGA 设备（class 3）的 BAR0 帧缓冲地址
pci_find_vga_fb:
    push r15
    xor r15d, r15d
.loop:
    cmp r15d, 32
    jae .notfound
    mov edi, 0
    mov esi, r15d
    xor edx, edx
    xor ecx, ecx
    call pci_read_config
    movzx eax, ax
    cmp eax, 0xFFFF
    je .next
    mov edi, 0
    mov esi, r15d
    xor edx, edx
    mov ecx, 8
    call pci_read_config
    shr eax, 24
    cmp eax, 3
    je .found
.next:
    inc r15d
    jmp .loop
.found:
    mov edi, 0
    mov esi, r15d
    xor edx, edx
    mov ecx, 0x10                    ; BAR0（QEMU stdvga 帧缓冲）
    call pci_read_config
    and eax, 0xFFFFFFF0
    test eax, eax
    jz .notfound
    pop r15
    ret
.notfound:
    xor eax, eax
    pop r15
    ret
