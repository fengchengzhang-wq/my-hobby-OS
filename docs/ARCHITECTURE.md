# 架构设计

## 1. 内存布局

```
物理地址                   虚拟地址
0x000000                  0xFFFFFFFF80000000  (KERNEL_VBASE)
├─ 0x200000  .boot 段     ├─ +0x200000 内核主体（.text/.rodata/.data/.bss）
│   引导代码/页表/栈       │   （由 2MB 大页映射，与 LMA 严格对应）
├─ _boot_size+0x200000    ├─ +1GB 映射结束
│   内核主体 LMA
└─ 0..4GB 恒等映射        └─ 物理 0..4GB 恒等映射
```

内核以物理 0x200000 加载（.boot），主体加载到 `_boot_size + 0x200000`，
虚拟基址 `0xFFFFFFFF80200000`。链接脚本对每个段做相同的 4KB 对齐，
保证 VMA 与 LMA 一一对应（`LMA = VMA - KERNEL_VBASE + _boot_size`）。

## 2. 启动流程

1. **Multiboot 探测**：GRUB 走 Multiboot2，QEMU -kernel 走 Multiboot1；
   保存魔数与引导信息指针。
2. **VBE 回退**：若 loader 未提供 32bpp 线性帧缓冲，通过 Bochs VBE
   寄存器（0x1CE/0x1CF）设置 1024×768×32 并启用 LFB；
   帧缓冲物理地址在 `init_framebuffer` 阶段从 PCI BAR0 自动探测。
3. **页表**：PML4[0]→4 张 P2 覆盖 4GB 恒等映射；PML4[511]→高半区 1GB。
4. **CR4.PAE → EFER.LME → CR0.PG → 远跳转**进入长模式。
5. **解析引导信息**：内存映射（注意 MB2 tag 的 entry_size 字段）、
   帧缓冲参数、RSDP、命令行。
6. **跳转 main**：初始化各子系统。

## 3. 子系统初始化顺序（main.asm）

```
串口 → GDT/TSS → IDT → PIC → PMM → VMM → 堆 → 帧缓冲 →
键盘 → 鼠标 → 定时器 → RTC → PCI → ATA → KAPI → syscall →
驱动注册表 → 系统报告 → 窗口管理器 → STI → 主循环
```

## 4. 中断架构

- `idt.asm` 用 `isr_table`（256 个入口地址）初始化全部向量。
- 异常：stub 压入向量/错误码 → 保存 15 个通用寄存器（`RegFrame`）→
  `exception_handler`（串口日志 + 蓝屏 dump）。
- IRQ：stub 压入向量 → `irq_dispatch` 查注册表调用处理函数 →
  统一发送 EOI → `iretq`。`irq_register(vector, handler)` 供驱动注册。

## 5. 图形管线

```
应用绘制 → 目标抽象（fb_set_target，默认主 backbuffer）
        → 脏矩形合并（fb_mark_dirty）
        → fb_flip：仅拷贝脏区域到真实帧缓冲（rep movsq）
```

窗口合成：桌面（渐变背景 + 任务栏 + 时钟 + 窗口按钮）→
窗口（后到前：边框 + 渐变标题栏 + 标题 + 关闭按钮 + 客户区 blit）→
光标（XOR 绘制，最后覆盖）。

## 6. 已知限制

- QEMU 6.2 的 `-kernel` 不支持 ELF64 多引导，完整 GUI 需 GRUB ISO；
  QEMU 7.1+ 支持直启。
- PS/2 鼠标在 QEMU 虚拟化下的数据包流对齐存在偶发错位
  （真实硬件与 GRUB 场景下按标准协议工作）。
- 当前为单核、无用户态；syscall 层与 TSS.rsp0 已为多态预留。

