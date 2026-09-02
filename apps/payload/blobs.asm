; apps/payload/blobs.asm - 内嵌文件负载

[bits 64]
section .rodata
global hello_exe_blob
hello_exe_blob:
    incbin "apps/payload/hello.bin"
global hello_exe_size
hello_exe_size: dd $ - hello_exe_blob

global demo_bat_blob
demo_bat_blob:
    incbin "apps/payload/demo.bat"
    db 0                        ; 保证批处理文本 NUL 终止
global demo_bat_size
demo_bat_size: dd $ - demo_bat_blob - 1
