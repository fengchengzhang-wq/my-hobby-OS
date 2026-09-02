# 驱动框架与驱动库

## 1. Driver Registry（sys/drvreg.asm）

所有驱动以 `Driver` 结构体（`inc/driver.inc`）注册：

```asm
struc Driver
    .name  resq 1   ; 名称字符串
    .kind  resd 1   ; DRV_KIND_*（字符/块/网络/定时/输入/GPU/总线/杂项）
    .state resd 1   ; 注册/初始化/错误
    .init  resq 1   ; 初始化函数
    .fini  resq 1
    .ops   resq 1   ; 驱动私有操作表
    .priv  resq 1
    .next  resq 1
endstruc
```

接口：`driver_register` / `driver_unregister` / `driver_find` /
`driver_init_all` / `driver_list_print`。驱动在各自 `init_*` 中自注册，
启动日志会打印完整注册表。

## 2. IRQ 注册框架（isr.asm）

```asm
irq_register(vector, handler, ctx)    ; 0 成功 / -1 失败
irq_unregister(vector)
```

分发器统一处理 EOI，处理函数无需关心中断结束。

## 3. 驱动清单

| 驱动 | 文件 | 类型 | 说明 |
|------|------|------|------|
| COM1 串口 | `drivers/serial.asm` | 字符 | 115200 8N1 + 格式化输出 |
| VBE 帧缓冲 | `drivers/framebuffer.asm` | GPU | 双缓冲 + 脏矩形 |
| PS/2 键盘 | `drivers/keyboard.asm` | 输入 | 扫描码集 1 + 修饰键 |
| PS/2 鼠标 | `drivers/mouse.asm` | 输入 | 3 字节数据包 + 重同步 |
| PIT 定时器 | `drivers/timer.asm` | 定时 | 100Hz + tick/睡眠 |
| CMOS RTC | `drivers/rtc.asm` | 杂项 | 实时时钟读取 |
| PCI 总线 | `drivers/pci.asm` | 总线 | 配置空间 + 枚举 + 查找 |
| ATA PIO | `drivers/ata.asm` | 块 | LBA28 读写 + 识别 |
| I/O HAL | `drivers/io.asm` | 杂项 | in/out 封装 + 延迟 |
| PC 扬声器 | `drivers/speaker.asm` | 杂项 | PIT 通道 2 发声 |

## 4. I/O HAL（drivers/io.asm）

```asm
io_outb / io_outw / io_outl(port, value)
io_inb / io_inw / io_inl(port) -> rax
io_wait()          ; ISA 延迟
io_delay(n)
```

## 5. PCI（drivers/pci.asm）

```asm
pci_read_config(bus, dev, func, reg) -> dword
pci_scan()                     ; 枚举 bus 0-1
pci_find(class, subclass, vendor) -> PciDevice*
pci_find_vga_fb()              ; VGA BAR0 帧缓冲地址（QEMU std VGA）
```

## 6. ATA PIO（drivers/ata.asm）

```asm
ata_read_sectors(lba, count, buf)    ; 0 成功 / -1 失败
ata_write_sectors(lba, count, buf)
ata_identify(buf)                    ; 读取识别数据
```

## 7. 扩展新驱动

1. 定义 `Driver` 结构体与 `init_*` 函数；
2. 在 `init_*` 中调用 `driver_register`；
3. 需要硬件中断时调用 `irq_register`；
4. 需要对外服务时通过 `kapi_register` 暴露名称。

## 8. 驱动扩展组件

驱动可通过 `driver_register` 在运行时注册（设备管理器实时列出）。
演示：软件中心的 Beeper 包安装后注册驱动描述符，设备管理器提供
「Test Speaker」硬件测试（880Hz/440Hz 双音）。
