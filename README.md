# MyOS - x86_64 纯汇编窗口化操作系统

一个完全用 NASM 汇编编写的 x86_64 图形操作系统，可在 QEMU 中直接运行。
包含完整的长模式引导、内存管理、中断处理、帧缓冲图形、窗口管理器、
PS/2 键盘/鼠标驱动、PIT 定时器，以及面向可扩展性的内核 API（KAPI）、
系统调用层和驱动注册框架。

## 快速开始

环境要求：NASM >= 2.15、GNU ld >= 2.38、QEMU >= 6.2（推荐 8.0+）、
GRUB 工具链（`grub-mkrescue`）。

```bash
# 构建并制作 GRUB 启动 ISO
make iso

# 在 QEMU 中运行（推荐：完整 GUI）
make run-iso

# QEMU 8.0+ 可以直接 -kernel 启动
make run

# 无头自动测试（捕获串口日志）
make test

# 调试模式（记录中断到 qemu.log）
make debug

# 清理
make clean
```

> 注意：QEMU 6.2 的 `-kernel` 加载器不支持 ELF64 多引导内核，因此完整
> GUI 请使用 `make run-iso`（GRUB 路径）。QEMU 7.1+ 支持多引导2 帧缓冲
> 的 `-kernel` 直启。

## 功能特性

- **双头引导**：Multiboot1（QEMU -kernel 兼容）+ Multiboot2（GRUB ISO，PRD 推荐）
- **长模式初始化**：4GB 恒等映射 + 高半区内核（`0xFFFFFFFF80000000`），
  完整的实模式 → 保护模式 → 长模式切换
- **内存管理**
  - 位图物理内存分配器（`bsf` 加速，O(1) 附近分配）
  - 四级页表虚拟内存（`vmm_map` / `vmm_unmap`）
  - 带合并与双链表的内核堆（`kmalloc` / `kfree`，16 字节对齐）
- **中断系统**：256 向量 IDT、异常处理（蓝屏 + 寄存器 dump + 串口日志）、
  8259 PIC、可注册的 IRQ 分发框架
- **图形子系统**：VBE 帧缓冲（1024×768×32，Bochs VBE + PCI BAR 自动探测）、
  双缓冲、脏矩形刷新、8×16 位图字体、基础图元与 blit
- **窗口管理器**：窗口创建/销毁/移动/焦点、渐变蓝色标题栏、关闭按钮、
  拖拽、任务栏（窗口列表 + 时钟）、XOR 鼠标光标
- **输入**：完整 PS/2 扫描码集 1（Shift/Ctrl/Alt/Caps 修饰键）、
  键盘事件环形缓冲、PS/2 鼠标 3 字节数据包解析
- **定时器**：PIT 100Hz，64 位 tick 计数，`sleep` / `uptime`
- **串口调试**：COM1 115200 8N1，格式化输出（`serial_printf`）
- **可扩展性（工业级）**
  - KAPI 内核 API 注册表（按名称动态解析，类似 `EXPORT_SYMBOL`）
  - SYSCALL/SYSRET 系统调用层（MSR STAR/LSTAR/SFMASK）
  - 驱动注册框架（Driver Registry，按名称查找/初始化）
  - PCI 总线枚举、ATA PIO 磁盘、CMOS RTC、I/O HAL 驱动库
- **应用层（TaskFlow 等）**
  - TaskFlow 任务看板：三列看板、增删改、移动、优先级、搜索、保存/载入
  - 软件中心：软件包安装/卸载/运行
  - 设备管理器：驱动列表 + 扬声器测试
  - 控制台：运行 .exe / .bat 并显示输出
- **UI 视觉**：极简浅色主题 + 柔和投影 + 立体按键（视觉立体感 + 阴影过渡）
- **字体**：8x16 ASCII + 16x16 简体中文点阵（GB2312 一级 3755 字 +
  常用标点，共 3883 字），界面与控制台均支持 UTF-8 混排中文
- **文件格式组件**：MyOS EXE（.exe）、批处理（.bat）、软件包（.app）、
  任务文件（tasks.tsk）、虚拟文件系统（VFS）

## 目录结构

```
.
├── boot.asm          # 双头引导 + 长模式 + 引导信息解析
├── main.asm          # 内核入口与子系统初始化
├── gdt.asm           # 完整 GDT + TSS
├── idt.asm           # IDT 全量初始化 + PIC
├── isr.asm           # 异常/IRQ 分发框架
├── linker.ld         # 高半区链接脚本
├── Makefile
├── grub.cfg
├── inc/              # 公共结构体与常量头
├── mm/               # 物理内存 / 虚拟内存 / 堆
├── drivers/          # 帧缓冲 / 键盘 / 鼠标 / 定时器 / 串口 /
│                     # I/O HAL / RTC / PCI / ATA
├── gui/              # 窗口 / 窗口管理器 / 桌面 / 光标
├── lib/              # 字符串 / 数学 / 格式化
├── api/              # KAPI 注册表 + 系统调用层
├── sys/              # 驱动注册框架 + Panic
├── tools/            # 字体生成工具
└── docs/             # 架构 / API / 驱动文档 + 截图
```

## 文档

- [架构设计](docs/ARCHITECTURE.md)
- [API 与 ABI](docs/API.md)
- [驱动框架](docs/DRIVERS.md)
- [需求规格](PRD.md)

## TaskFlow 功能映射（PRD P0 子集）

| PRD | 说明 | 实现 |
|-----|------|------|
| F-003 | 任务创建与编辑 | 看板 Add Task / 编辑标题与优先级 |
| F-004 | 看板视图 | 三列看板 + <-/-> 移动卡片 + 选中 |
| F-005 | 分配与通知 | 负责人字段（卡片展示） |
| F-007 | 基础搜索 | 顶部搜索框实时过滤 |
| F-008 | 保存/载入 | tasks.tsk 虚拟文件持久化 |
| 统计 | 完成率 | 列头实时计数 |

## 已解决的工程问题（开发记录）

- 链接器 LMA/VMA 对齐漂移导致高半区数据错位（用每段 4KB 同步对齐修复）
- Multiboot2 内存映射 tag 的 `entry_size` 字段（条目从 +16 开始）
- 帧缓冲偏移公式 `(y*pitch+x)<<2` 把 y 分量误乘 4（应为 `y*pitch+x*4`），
  导致写穿到堆区
- QEMU std VGA 的 LFB 地址在 PCI BAR0（0xFD000000）而非固定地址
- NASM 32 位立即数符号扩展陷阱（`mov [mem], 0xE0000000` 变负地址）
- PS/2 键盘/鼠标 ACK 残留导致 IRQ 时序错乱（排空 + 重同步修复）
- EXE 负载未带 52 字节头且 magic 常量笔误（"MYOSX1" 写成 "MYOXX1"），
  加载器校验失败导致静默返回 -1（已统一为 8 字节 magic 直接比较）
- `.exe` 负载字符串原放在 `.rodata`，而 exec 只拷贝 52 字节头后的代码区，
  `[rel]` 寻址会指向未拷贝内存、输出为空（负载字符串现内联在代码区内，
  `csize` 一并包含；demo.bat 内嵌负载追加 NUL 终止符）
- `fb_draw_char` 把字模位 7 画在 x+7，导致整屏文字水平镜像、UI 观感崩坏
  （已改为 bit7->x+0；OCR 复核 "TaskFlow" 逐字可读）
- 中文字库由 tools/genfont_cjk.py 从 Noto Sans CJK SC 降采样为 16x16 点阵
  （assets/cjk16.bin），fb_draw_string / 控制台按 UTF-8 解码混排渲染
- ui_button/ui_textfield 把标签源放在 rdx 而 ui_cpyn 读取 rsi，导致所有
  按钮/输入框标签为空（已修正参数传递）
- fb_draw_border 从栈读线宽而调用方全部用 r9d 传参，线宽为垃圾值
  （改为按 r9d 约定读取）
- ui_draw_button 顶部填充后继续使用被 fb_draw_rect 破坏的 rax 计算底部
  矩形，y/h 变成巨值，画出贯穿窗口的巨型色块（保存 h/2 于栈修复）
- 拖拽状态改为“左键按住才移动、任一时刻检测到松开即复位”，避免鼠标
  释放事件丢失/毛刺导致窗口拖住卡死或松开后仍被吸附
- 点击文本框聚焦时 ui_clear_focus 收到的是残留寄存器而非窗口指针，
  解引用垃圾地址触发 #GP 使系统整机冻结（补回 mov rdi,r12）
