; inc/pkg.inc - 软件包结构

PKG_APP    equ 1
PKG_DRIVER equ 2
PKG_SYS    equ 3

struc PkgEnt
    .id     resd 1
    .name   resb 40
    .kind   resd 1
    .vname  resb 40       ; VFS 文件名（无则为空）
    .vtype  resd 1
    .blob   resq 1        ; 内置负载指针
    .size   resd 1
    .inst   resd 1        ; 1=已安装
    .launch resq 1        ; 打开/运行回调（0 则按文件类型执行）
    .desc   resb 64
    .next   resq 1
endstruc
