; inc/syscall.inc - 系统调用号（用户态 API）

SYS_EXIT        equ 0
SYS_WRITE       equ 1
SYS_GET_TICKS   equ 2
SYS_SLEEP       equ 3
SYS_ALLOC       equ 4
SYS_FREE        equ 5
SYS_TIME        equ 6
SYS_MOUSE       equ 7
SYS_KAPI_LOOKUP equ 8

struc SysTime
    .sec   resd 1
    .min   resd 1
    .hour  resd 1
    .day   resd 1
    .mon   resd 1
    .year  resd 1
endstruc

