# API 与 ABI

## 1. 调用约定

内核内部采用 System V AMD64：参数依次在 `rdi, rsi, rdx, rcx, r8, r9`，
其余走栈；`rax` 返回；`rbx, rbp, r12-r15` 被调用方保存。

## 2. 内核 API 注册表（KAPI）

`api/kapi.asm` 提供按名称动态解析的服务注册表（类似 Linux `EXPORT_SYMBOL`）。
驱动与模块可通过名称获取服务函数指针，无需编译期链接依赖。

```asm
; 注册：kapi_register(name, func)
; 解析：kapi_resolve(name) -> func 或 0
```

内置服务：

| 名称 | 函数 |
|------|------|
| `pmm.alloc` | `pmm_alloc` |
| `pmm.free` | `pmm_free` |
| `pmm.alloc_contig` | `pmm_alloc_contig` |
| `kmalloc` / `kfree` | 内核堆 |
| `serial.print` | `serial_write_string` |
| `timer.ticks` | `get_ticks` |
| `timer.sleep` | `timer_sleep` |
| `irq.register` | `irq_register` |
| `fb.draw_string` / `fb.clear` | 图形输出 |
| `panic` | 内核 Panic |
| `ata.read_sectors` | ATA 磁盘读 |

## 3. 系统调用层（syscall）

`api/syscall.asm` 通过 `STAR/LSTAR/SFMASK` 设置 `SYSCALL/SYSRET`，
为未来用户态预留。调用号定义在 `inc/syscall.inc`：

| 号 | 名称 | 说明 |
|----|------|------|
| 0 | `SYS_EXIT` | 退出 |
| 1 | `SYS_WRITE` | 写控制台 |
| 2 | `SYS_GET_TICKS` | 系统 tick |
| 3 | `SYS_SLEEP` | 忙等待 ms |
| 4 | `SYS_ALLOC` | 内核堆分配 |
| 5 | `SYS_FREE` | 释放 |
| 6 | `SYS_TIME` | RTC 时间 |
| 7 | `SYS_MOUSE` | 鼠标状态 |
| 8 | `SYS_KAPI_LOOKUP` | 内核 API 解析 |

## 4. 图形绘制接口

```asm
fb_draw_pixel(x, y, color)          ; rdi, rsi, edx
fb_draw_rect(x, y, w, h, color)     ; rdi, rsi, rdx, rcx, r8d
fb_draw_hline / fb_draw_vline       ; 矩形特例
fb_draw_char(x, y, ch, fg, bg)      ; bg=-1 透明
fb_draw_string(x, y, str, fg, bg)
fb_blit(src, src_pitch, dx, dy, w, h)
fb_set_target(base, w, h, pitch)    ; 绘制目标切换（窗口客户区）
fb_reset_target()                   ; 恢复主 backbuffer
fb_flip()                           ; 脏矩形刷新
```

## 5. 内存接口

```asm
pmm_alloc()                 ; 返回物理页地址（0 失败）
pmm_free(addr)
pmm_alloc_contig(pages)
vmm_map(virt, phys, size)   ; 4KB 页映射
vmm_unmap(virt, size)
kmalloc(size)               ; 16 字节对齐，0 失败
kfree(ptr)                  ; 非法指针触发 Panic
```

## 6. 窗口接口

```asm
window_create(title, x, y, w, h)    ; -> Window*（0 失败）
window_destroy(win)
window_move(win, dx, dy)            ; 带边界检查
window_focus(win)                   ; 置顶 + 焦点
```

`Window.paint_fn` 为客户区绘制回调（0 = 默认绘制器），应用可自定义。

## 7. 串口调试

```asm
serial_printf(fmt, ...)   ; 支持 %s %c %d %x %p %%
serial_write_hex64(v)
serial_write_dec64(v)
```

## 8. 应用与系统服务 API

```asm
; 虚拟文件系统
vfs_add_blob(name, type, data, size)   ; 注册文件（type: 0raw/1exe/2bat/3app/4drv）
vfs_find(name) -> VFile*
vfs_delete(name)

; 可执行 / 批处理
exec_run_file(name)                    ; 加载 .exe 到内核控制台运行
batch_run(text)                        ; 解释 .bat 命令（echo/cls/sleep/list/run/help）
console_clear / console_write(str)     ; 应用控制台缓冲

; 软件包管理
pkg_init / pkg_add / pkg_add_file
pkg_install(name) / pkg_uninstall(name) / pkg_run(name) / pkg_find(name)

; 设备/驱动
driver_register(drv)                   ; 运行时注册驱动
speaker_beep_ms(freq, ms)              ; PC 扬声器（PIT ch2）
```

### 控件系统（gui/ui.asm）

```asm
ui_button(win, x, y, w, h, label, cb)  ; 立体按钮，cb(win, ctrl)
ui_textfield(win, x, y, w, h, label, cb)
ui_draw_all(win)                       ; 绘制全部控件（客户区内）
ui_mouse_event(win, type, x, y)        ; 控件事件路由
ui_key_event(win, ch)
```

应用窗口通过 `Window.paint_fn` / `Window.input_fn` 接入：
`input_fn(win, UI_EV_*, x, y, buttons, key)`。
