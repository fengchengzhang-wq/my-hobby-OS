; hello.exe 负载（-f bin 编译，含 52 字节 EXE 头 + PIC 代码）
; 头布局与 sys/exec.asm ExeHdr 一致：
;   0:  magic "MYOSX1\0\0"（8 字节）
;   8:  entry  = 代码内偏移（代码加载后入口即代码首字节，故为 0）
;   12: csize  = 代码长度
;   16: rsvd
;   20: name[32]
;   52: 代码
BITS 64
global _start
section .text
_start:                         ; 文件偏移 0 = EXE 头
    db "MYOSX1", 0, 0
    dd 0                        ; entry（相对代码起始）
    dd code_end - code_start    ; csize
    dd 0                        ; rsvd
    times 32 db 0               ; name
code_start:
    push rbx
    mov rbx, rdi                ; print_fn
    lea rdi, [rel msg1]
    call rbx
    lea rdi, [rel msg2]
    call rbx
    lea rdi, [rel msg3]
    call rbx
    mov rax, 7
    pop rbx
    ret
    ; 注意：exec 加载器只拷贝 code_start..code_end，字符串必须内联在
    ; 代码区内（不能放 .rodata，否则 [rel] 会指向未拷贝区域）
msg1: db "Hello from MyOS EXE!", 13, 10, 0
msg2: db "EXE executed OK (ret=7)", 13, 10, 0
msg3: db "中文字符集渲染正常", 13, 10, 0
code_end:
