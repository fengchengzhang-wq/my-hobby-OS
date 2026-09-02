; inc/ui.inc - 轻量控件系统与极简主题

struc Control
    .type  resd 1   ; CTRL_BUTTON / CTRL_FIELD / CTRL_LABEL / CTRL_CUSTOM
    .x     resd 1
    .y     resd 1
    .w     resd 1
    .h     resd 1
    .state resd 1   ; 1=pressed 2=hover 4=focus
    .label resb 40
    .value resb 192
    .cb    resq 1   ; cb(win, ctrl)
    .next  resq 1
endstruc

CTRL_BUTTON equ 1
CTRL_FIELD  equ 2
CTRL_LABEL  equ 3

CTRL_ST_PRESSED equ 1
CTRL_ST_HOVER   equ 2
CTRL_ST_FOCUS   equ 4

; ---------- 极简浅色主题 ----------
THEME_BG_TOP     equ 0xFFE8EDF4   ; 桌面渐变上
THEME_BG_BOT     equ 0xFFC9D3E1   ; 桌面渐变下
THEME_TASKBAR    equ 0xFFF4F6FA   ; 任务栏
THEME_TASKBAR_LN equ 0xFFD4DAE3

THEME_WIN_BG     equ 0xFFF7F8FA   ; 窗口客户区
THEME_WIN_BORDER equ 0xFFB9C2CE
THEME_TITLE_TOP  equ 0xFFFBFCFE   ; 标题栏渐变
THEME_TITLE_BOT  equ 0xFFE9EDF3
THEME_TITLE_TXT  equ 0xFF334155
THEME_ACCENT     equ 0xFF3B82F6   ; 焦点强调蓝
THEME_ACCENT_DK  equ 0xFF2563EB

THEME_BTN_TOP    equ 0xFFFBFCFE
THEME_BTN_BOT    equ 0xFFE3E8EF
THEME_BTN_EDGE   equ 0xFFC7CFDA
THEME_BTN_TXT    equ 0xFF26313D
THEME_BTN_HI     equ 0xFFEEF3FB

THEME_FIELD_BG   equ 0xFFFFFFFF
THEME_FIELD_EDGE equ 0xFFC3CBD6
THEME_TEXT       equ 0xFF1F2937
THEME_TEXT_DIM   equ 0xFF7A8494
THEME_SEL        equ 0xFFDCE9FF

THEME_CARD_BG    equ 0xFFFFFFFF
THEME_CARD_EDGE  equ 0xFFE0E5EC
THEME_COL_BG     equ 0xFFECEFF4

PRIO_URGENT equ 0xFFE5484D
PRIO_HIGH   equ 0xFFF5A524
PRIO_MID    equ 0xFF3B82F6
PRIO_LOW    equ 0xFF94A3B8
