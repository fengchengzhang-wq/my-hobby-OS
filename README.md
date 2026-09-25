# MyOS - x86_64 Pure Assembly Windowed Operating System

A graphical operating system written entirely in NASM assembly, running directly in QEMU.
It includes complete long mode boot, memory management, interrupt handling, framebuffer graphics, a window manager,
PS/2 keyboard/mouse drivers, a PIT timer, and an extensibility-oriented kernel API (KAPI),
system call layer, and driver registration framework.

## Quick Start

Requirements: NASM >= 2.15, GNU ld >= 2.38, QEMU >= 6.2 (8.0+ recommended),
GRUB toolchain (`grub-mkrescue`).

```bash
# Build and create a GRUB boot ISO
make iso

# Run in QEMU (recommended: full GUI)
make run-iso

# QEMU 8.0+ can boot directly with -kernel
make run

# Headless automated test (capture serial log)
make test

# Debug mode (log interrupts to qemu.log)
make debug

# Clean
make clean
```

> Note: QEMU 6.2's `-kernel` loader does not support ELF64 multiboot kernels, so use
> `make run-iso` (GRUB path) for the full GUI. QEMU 7.1+ supports Multiboot2 framebuffer
> `-kernel` direct boot.

## Features

- **Dual-header boot**: Multiboot1 (QEMU -kernel compatible) + Multiboot2 (GRUB ISO, PRD recommended)
- **Long mode initialization**: 4GB identity mapping + higher-half kernel (`0xFFFFFFFF80000000`),
  complete real mode → protected mode → long mode switch
- **Memory management**
  - Bitmap physical memory allocator (`bsf` accelerated, near O(1) allocation)
  - Four-level page table virtual memory (`vmm_map` / `vmm_unmap`)
  - Kernel heap with coalescing and doubly linked list (`kmalloc` / `kfree`, 16-byte aligned)
- **Interrupt system**: 256-vector IDT, exception handling (blue screen + register dump +
  serial log), 8259 PIC, registerable IRQ dispatch framework
- **Graphics subsystem**: VBE framebuffer (1024×768×32, Bochs VBE + PCI BAR auto-detection),
  double buffering, dirty rectangle refresh, 8×16 bitmap font, basic primitives and blit
- **Window manager**: window create/destroy/move/focus, gradient blue title bar, close button,
  dragging, taskbar (window list + clock), XOR mouse cursor
- **Input**: complete PS/2 scan code set 1 (Shift/Ctrl/Alt/Caps modifiers),
  keyboard event ring buffer, PS/2 mouse 3-byte packet parsing
- **Timer**: PIT 100Hz, 64-bit tick counter, `sleep` / `uptime`
- **Serial debugging**: COM1 115200 8N1, formatted output (`serial_printf`)
- **Extensibility (industrial-grade)**
  - KAPI kernel API registry (dynamic resolution by name, similar to `EXPORT_SYMBOL`)
  - SYSCALL/SYSRET system call layer (MSR STAR/LSTAR/SFMASK)
  - Driver registration framework (Driver Registry, lookup/init by name)
  - PCI bus enumeration, ATA PIO disk, CMOS RTC, I/O HAL driver library
  - ACPI table parsing (RSDP/RSDT/XSDT + FACP/MADT/HPET), MADT enumeration of CPU/LAPIC/IOAPIC, S5 soft poweroff
  - RTL8139 NIC + ARP/IPv4/ICMP: ARP gateway resolution, ICMP Echo reply (PCI probe + RX ring + TX descriptor)
  - AC'97 audio: mixer (master volume/PCM out), 48kHz sample rate, PCM out bus-master DMA square wave playback
  - SMP: xAPIC enable + AP boot (0x8000 trampoline, INIT-SIPI-SIPI) + IOAPIC redirection
    (IRQ0→GSI 2 etc. mapped per MADT ISO), interrupts delivered via IOAPIC after masking 8259
  - DWM layered windows: WS_EX_LAYERED per-pixel Alpha + color-key composition,
    UpdateLayeredWindow / SetLayeredWindowAttributes
- **Application layer (TaskFlow, etc.)**
  - TaskFlow task board: three-column board, add/delete/edit, move, priority, search, save/load
  - Software Center: package install/uninstall/run
  - Device Manager: driver list + speaker test
  - Console: run .exe / .bat and display output
- **UI visuals**: minimalist light theme + soft shadows + 3D buttons (visual depth + shadow transitions)
- **Fonts**: 8x16 ASCII + 16x16 Simplified Chinese bitmap (GB2312 level 1 3755 characters +
  common punctuation, 3883 total), UI and console both support UTF-8 mixed Chinese
- **File format components**: MyOS EXE (.exe), batch (.bat), software package (.app),
  task file (tasks.tsk), virtual file system (VFS)
- **Win32 compatibility layer (corresponds to Windows Compatibility PRD v1.0)**:
  - Message subsystem: per-window 128-entry message queue, Post/Send/Get/Peek/Dispatch/
    TranslateMessage, WndProc, SetTimer/WM_TIMER, WM_* constants
  - Standard controls: Button / Edit / Static / ListBox / ComboBox / ScrollBar /
    ProgressBar (child windows + WM_COMMAND notifications)
  - Control interaction: Tab / Shift+Tab focus traversal (IsDialogMessage / WM_NEXTDLGCTL /
    WS_TABSTOP wrap-around), Edit supports caret insert/backspace/arrow keys and
    Ctrl+C / Ctrl+X / Ctrl+V clipboard, child control dirty auto-repaint
  - Object manager: object types/reference counting/namespace + per-process handle table (increments by 4),
    CloseHandle/DuplicateHandle, Event/Mutex/Semaphore
  - Window API: CreateWindowEx / CreateChildWindow / DestroyWindow /
    ShowWindow / MoveWindow / InvalidateRect / SetFocus / GetDC / MessageBox
  - PE loader: PE32+ parsing, section mapping, import table resolution (IAT backfill), DIR64 relocation,
    entry call and ExitProcess return; `tools/mkpe.py` can generate demo PE64
  - GDI: DC/bitmap/brush/pen/font, text, BitBlt/StretchBlt/TransparentBlt,
    gradient fill, Alpha blending, path recording and stroking
  - Registry: HKEY tree + RegCreateKeyEx/RegSetValueEx/RegQueryValueEx etc.
  - Driver framework: IRP structure/allocation/issue/completion, device tree (PCI enumeration nodes),
    PnP START IRP, power IRP, WM_DEVICECHANGE
  - Security: token/integrity level, DACL and AccessCheck (MIC No-Write-Up verified in practice)
  - Clipboard: text clipboard + Win32 Clipboard API subset (OpenClipboard/
    EmptyClipboard/SetClipboardData/GetClipboardData/CloseClipboard)
  - Demo application: desktop "Win32 Compatibility Demo" window (Edit + Button + ListBox + Progress)
- **Detailed description and requirements mapping**: [docs/WIN32_COMPAT.md](docs/WIN32_COMPAT.md)

## Directory Structure

```
.
├── boot.asm          # Dual-header boot + long mode + boot info parsing
├── main.asm          # Kernel entry and subsystem initialization
├── gdt.asm           # Full GDT + TSS
├── idt.asm           # Full IDT initialization + PIC
├── isr.asm           # Exception/IRQ dispatch framework
├── linker.ld         # Higher-half linker script
├── Makefile
├── grub.cfg
├── inc/              # Common structures and constants headers
├── mm/               # Physical memory / virtual memory / heap
├── drivers/          # Framebuffer / keyboard / mouse / timer / serial /
│                     # I/O HAL / RTC / PCI / ATA
├── gui/              # Window / window manager / desktop / cursor
├── lib/              # String / math / formatting
├── api/              # KAPI registry + syscall layer
├── sys/              # Driver registration framework + Panic
├── tools/            # Font generation tools
└── docs/             # Architecture / API / driver docs + screenshots
```

## Documentation

- [Architecture Design](docs/ARCHITECTURE.md)
- [API and ABI](docs/API.md)
- [Driver Framework](docs/DRIVERS.md)
- [Unimplemented Features List](docs/UNIMPLEMENTED.md)
- [Win32 Compatibility Layer](docs/WIN32_COMPAT.md)
- [Requirements Specification](PRD.md)

## TaskFlow Feature Mapping (PRD P0 subset)

| PRD | Description | Implementation |
|-----|-------------|----------------|
| F-003 | Task creation and editing | Board Add Task / edit title and priority |
| F-004 | Board view | Three-column board + <-/-> move card + select |
| F-005 | Assignment and notification | Assignee field (shown on card) |
| F-007 | Basic search | Top search box real-time filtering |
| F-008 | Save/load | tasks.tsk virtual file persistence |
| Stats | Completion rate | Real-time column header counts |

## Solved Engineering Problems (Development Log)

- Linker LMA/VMA alignment drift caused higher-half data misplacement (fixed with per-section 4KB synchronized alignment)
- Multiboot2 memory map tag's `entry_size` field (entries start at +16)
- Framebuffer offset formula `(y*pitch+x)<<2` multiplied the y component by 4 (should be `y*pitch+x*4`),
  causing writes through to the heap region
- QEMU std VGA's LFB address is in PCI BAR0 (0xFD000000) rather than a fixed address
- NASM 32-bit immediate sign-extension trap (`mov [mem], 0xE0000000` becomes a negative address)
- PS/2 keyboard/mouse ACK residue caused IRQ timing corruption (fixed by draining + resynchronization)
- Win32 compatibility layer implementation notes: `fb_draw_rect` clobbers rax (button drawing fixed),
  `gdi_begin` once used esi to load width, overwriting the DC pointer (fixed),
  `ui_clear_focus` parameters were not restored, causing #GP when clicking a text box (fixed)
- The kernel heap was originally 4MB, filled up by the client-area buffers of four application windows,
  causing control state allocation for the demo window to fail (button clicks did nothing) — the heap
  was expanded to 16MB, and a "heap out of space" serial warning was added to kmalloc; after the fix,
  the Win32 demo's "input → click → add to list → progress bar advances" full chain passed in real testing
- EXE payload did not carry the 52-byte header and the magic constant had a typo ("MYOSX1" written as "MYOXX1"),
  so loader validation failed and silently returned -1 (now unified to direct 8-byte magic comparison)
- `.exe` payload strings were originally placed in `.rodata`, but exec only copies the code area after the
  52-byte header, so `[rel]` addressing pointed to uncopied memory and output was empty (payload strings are now
  inlined in the code area, included in `csize`; demo.bat embedded payload appends a NUL terminator)
- `fb_draw_char` drew font bit 7 at x+7, causing the entire screen's text to be horizontally mirrored and
  ruining the UI (changed to bit7->x+0; OCR recheck confirms "TaskFlow" is readable character by character)
- The Chinese font library is downsampled from Noto Sans CJK SC by tools/genfont_cjk.py into a 16x16 bitmap
  (assets/cjk16.bin); fb_draw_string / console decode UTF-8 and render mixed text
- ui_button/ui_textfield put the label source in rdx while ui_cpyn reads rsi, causing all button/input
  labels to be empty (parameter passing fixed)
- fb_draw_border read line width from the stack while all callers passed it via r9d, so line width was garbage
  (changed to read per the r9d convention)
- ui_draw_button continued using rax clobbered by fb_draw_rect after filling the top to calculate the bottom
  rectangle, making y/h huge values and drawing a giant color block spanning the window (fixed by saving h/2 on the stack)
- Drag state was changed to "move only while the left button is held, reset as soon as release is detected at any time",
  avoiding mouse release event loss/glitches causing the window drag to get stuck or remain attached after release
- When clicking a text box to focus, ui_clear_focus received residual registers instead of the window pointer;
  dereferencing a garbage address triggered #GP and froze the whole system (restored mov rdi,r12)
- When the kernel physical end `_kernel_phys_end` was not page-aligned, PMM rounded down to reserve the kernel area,
  leaving the last page (a half page) in the free bitmap, where the heap allocator took it, causing a physical alias
  with `io_dummy_table` at the end of `.bss` — manifested as "#GP when merely linking clipboard.o".
  Fix: linker.ld aligns `_kernel_phys_end`, and the PMM reservation interval now rounds up
- `LB_ADDSTRING` had a fixed 32-byte entry but used `strcpy` to write, so long text overflowed and corrupted the heap;
  the TaskFlow search box (80 bytes) also had no truncation. Unified to the newly added `strlcpy`
  (always NUL-terminated, returns source length), and added control boundary self-checks
- `win32_pump` only checked the top-level window's `invalid`; child controls setting invalid did not trigger
  WM_PAINT, manifested as "input reaches state but the screen does not update"; changed to
  `win32_tree_invalid` to recursively check the subtree, and clear invalid after `paint_tree`
- WM_KEYDOWN's lParam is now encoded as `scan code | modifiers<<8` (`KEYLP_MOD_*`);
  Edit needs modifiers to distinguish Ctrl+C/V/X from normal letters; function keys with ASCII 0
  (arrow keys, etc.) now also continue to deliver WM_KEYDOWN

## M4 Platformization Progress (2026-09-20)

Boot self-test baseline: **42 PASS / 0 FAIL / 0 exceptions / 0 double frees** (reproduction command in
[docs/UNIMPLEMENTED.md](docs/UNIMPLEMENTED.md) appendix; network and audio self-tests require
`-netdev/-device rtl8139` and `-audiodev/-device AC97` parameters; SMP self-test requires
`-smp 2` or more; `make run-iso` already includes `-smp 2` and audio devices).

- **P-08 ACPI**: RSDP checksum + RSDT/XSDT auto-selection + FACP/MADT/HPET indexing;
  MADT enumerates CPU/LAPIC/IOAPIC; S5 soft poweroff (SLP_TYPa tries 7/5/0 in order)
- **P-05 Networking**: RTL8139 + ARP + IPv4 + ICMP Echo full-chain self-test passed.
  Key root cause: RTL8139's **CAPR = software read pointer − 16** (writing the packet header address directly
  makes the chip decide the RX ring has no space and silently drop all subsequent frames); also corrected the
  ring wrap modulus to 8K (same modulus as the chip)
- **P-07 Audio**: AC'97 codec handshake (VendorID=8384:7600, sample rate 48000 readback),
  mixer write/readback, PCM out DMA playing a 440Hz square wave. Key root causes: ① must first do a
  **GLOB_CNT cold reset** and wait for PCR, only then DMA advances; ② the BDL length field unit is
  **16-bit sample count** (byte count/2). External evidence: the file recorded with
  `-audiodev wav,path=/tmp/ac97.wav` is exactly a 0.24s 440Hz square wave
- **DWM layered windows**: `WS_EX_LAYERED` whole-window 0x00AARRGGBB (non-premultiplied) buffer,
  `fb_blend_argb` per-pixel Alpha + `LWA_ALPHA` constant Alpha + `LWA_COLORKEY`
  color-key composition, `UpdateLayeredWindow` / `Set/GetLayeredWindowAttributes` available;
  self-test uses pixel-level assertions (Alpha=0 and color key preserve background, Alpha=255 exact overlay,
  semi-transparent=0x00A04060, constant Alpha=0x00A04060, API round-trip consistent)
- **P-09 SMP + IOAPIC**: xAPIC enable (MSR 0x1B) + LAPIC programming (TPR/SVR/DFR/LDR);
  AP boot trampoline (physical 0x8000, real mode→protected mode→long mode, reusing BSP's CR3/PML4,
  INIT-SIPI-SIPI, one kernel stack page per AP), after which the AP uses CPUID to get its own APIC ID and
  records it (verified `-smp 2` → AP APIC ID=1 online); IOAPIC redirection table maps ISA IRQ→GSI per
  **MADT's Interrupt Source Override** (QEMU: IRQ0→GSI 2) then masks 8259, and `isr.asm` sends LAPIC EOI
  based on `apic_enabled`. Regression evidence: after masking PIC, PIT tick still advances; monitor injects
  `sendkey tab`/`sendkey o` and `mouse_move`, then screenshots are compared pixel by pixel; cursor moved from
  (0,0) to ≈(180,90), indicating IRQ1/IRQ12 are also delivered via IOAPIC
- Not yet started: USB (xHCI/UHCI + HID), TrueType, VSync/exposed-region precise repaint,
  AP scheduling and load balancing
