; inc/driver.inc - 驱动框架结构

struc Driver
    .name  resq 1
    .kind  resd 1
    .state resd 1
    .init  resq 1
    .fini  resq 1
    .ops   resq 1
    .priv  resq 1
    .next  resq 1
endstruc

DRV_KIND_CHAR  equ 1
DRV_KIND_BLOCK equ 2
DRV_KIND_NET   equ 3
DRV_KIND_TIMER equ 4
DRV_KIND_INPUT equ 5
DRV_KIND_GPU   equ 6
DRV_KIND_BUS   equ 7
DRV_KIND_MISC  equ 8

DRV_STATE_REGISTERED   equ 1
DRV_STATE_INITIALIZED  equ 2
DRV_STATE_ERROR        equ 3

