ASM = nasm
LD = ld
QEMU = qemu-system-x86_64
GRUB_RESCUE = grub-mkrescue

ASMFLAGS = -f elf64 -I inc
LDFLAGS = -T linker.ld -nostdlib -z max-page-size=0x1000
QEMUFLAGS = -m 128M -smp 1 -vga std -serial stdio -no-reboot -no-shutdown

# 按目录分组列出全部源文件
SRCS = boot.asm main.asm gdt.asm idt.asm isr.asm \
       mm/pmm.asm mm/vmm.asm mm/heap.asm \
       drivers/serial.asm drivers/framebuffer.asm drivers/font.asm \
       drivers/keyboard.asm drivers/mouse.asm drivers/timer.asm \
       drivers/io.asm drivers/rtc.asm drivers/pci.asm drivers/ata.asm \
       drivers/speaker.asm drivers/font_cjk.asm \
       gui/window.asm gui/wm.asm gui/desktop.asm gui/cursor.asm gui/ui.asm \
       lib/string.asm lib/math.asm lib/format.asm \
       api/kapi.asm api/syscall.asm sys/drvreg.asm sys/panic.asm \
       sys/vfs.asm sys/console.asm sys/exec.asm sys/batch.asm sys/pkg.asm \
       apps/payload/blobs.asm apps/taskflow.asm apps/center.asm \
       apps/devmgr.asm apps/console.asm

OBJS = $(SRCS:.asm=.o)

all: kernel.elf

kernel.elf: $(OBJS) linker.ld apps/payload/hello.bin
	$(LD) $(LDFLAGS) -o $@ $(filter-out linker.ld apps/payload/hello.bin,$^)

%.o: %.asm
	$(ASM) $(ASMFLAGS) -o $@ $<

drivers/font_cjk.o: drivers/font_cjk.asm assets/cjk16.bin

apps/payload/blobs.o: apps/payload/blobs.asm apps/payload/hello.bin

apps/payload/hello.bin: apps/payload/hello.asm
	$(ASM) -f bin -o $@ $<

clean:
	rm -f $(OBJS) kernel.elf

dist-clean: clean
	rm -rf iso iso-staging kernel.iso

# QEMU -kernel（QEMU >= 8.0 提供帧缓冲；6.2 走静态回退，串口可用）
run: kernel.elf
	$(QEMU) $(QEMUFLAGS) -kernel kernel.elf

# GRUB ISO（推荐，QEMU >= 6.2 完整 GUI）
run-iso: iso
	$(QEMU) $(QEMUFLAGS) -cdrom kernel.iso -boot d

debug: kernel.elf
	$(QEMU) $(QEMUFLAGS) -d int,cpu_reset -D qemu.log -kernel kernel.elf

iso: kernel.elf
	@tmpdir=$$(mktemp -d /tmp/myos-iso.XXXXXX); \
	mkdir -p $$tmpdir/boot/grub; \
	cp kernel.elf $$tmpdir/boot/kernel.elf; \
	cp grub.cfg $$tmpdir/boot/grub/grub.cfg; \
	$(GRUB_RESCUE) -o kernel.iso $$tmpdir; \
	rm -rf $$tmpdir

# 无头自动测试：捕获串口输出
test: kernel.elf
	timeout 12 $(QEMU) $(QEMUFLAGS) -display none -kernel kernel.elf 2>&1 | tee boot-test.log

.PHONY: all clean dist-clean run run-iso debug iso test
