; inc/events.inc - 输入事件类型与结构

EV_KEY_DOWN   equ 1
EV_KEY_UP     equ 2
EV_MOUSE_MOVE equ 3
EV_MOUSE_DOWN equ 4
EV_MOUSE_UP   equ 5

KBD_MOD_SHIFT equ 1
KBD_MOD_CTRL  equ 2
KBD_MOD_ALT   equ 4
KBD_MOD_CAPS  equ 8

struc KeyEvent
    .type     resd 1
    .scancode resd 1
    .ascii    resd 1
    .mods     resd 1
endstruc

KEY_BUF_SIZE  equ 128

struc MouseState
    .x       resd 1
    .y       resd 1
    .buttons resd 1
endstruc

