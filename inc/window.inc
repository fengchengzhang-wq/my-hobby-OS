; inc/window.inc - 窗口结构与窗口管理器常量

struc Window
    .id         resd 1
    .x          resd 1
    .y          resd 1
    .width      resd 1
    .height     resd 1
    .backbuffer resq 1
    .flags      resd 1
    .title      resb 64
    .paint_fn   resq 1   ; 客户区绘制回调（0 = 默认绘制器）
    .input_fn   resq 1   ; 应用输入回调（0 = 使用内置 ESC/拖拽语义）
    .controls   resq 1   ; UI 控件链表头
    .ui_focus   resq 1   ; 当前聚焦控件
    .ui_pressed resq 1   ; 当前按下的控件
    .user       resq 1   ; 应用私有数据指针
    .next       resq 1
endstruc

WIN_FLAG_VISIBLE   equ 1
WIN_FLAG_FOCUSED   equ 2
WIN_FLAG_CLOSEABLE equ 4

TITLE_HEIGHT equ 20

; 应用输入事件类型（input_fn 的 esi）
UI_EV_MOUSE_DOWN equ 1
UI_EV_MOUSE_UP   equ 2
UI_EV_MOUSE_MOVE equ 3
UI_EV_KEY        equ 4
