CC	:= gcc
CFLAGS	:= -nostdinc -I/usr/x86_64-linux-musl/include -Iinclude -Ix86/include -D_GNU_SOURCE -DKVMTOOLS_VERSION='"1.0"' -DBUILD_ARCH='"x86"' -g
BUILD	:= build

OBJS := devices.o irq.o kvm-cpu.o kvm.o kvm-ipc.o main.o builtin-debug.o builtin-run.o kvm-cmd.o mmio.o pci.o term.o
OBJS += $(addprefix disk/, core.o raw.o)
OBJS += $(addprefix hw/, serial.o rtc.o)
OBJS += $(addprefix virtio/, blk.o core.o pci.o pci-modern.o console.o)
OBJS += $(addprefix util/, init.o threadpool.o parse-options.o iovec.o rbtree.o rbtree-interval.o strbuf.o read-write.o util.o)
OBJS += $(addprefix x86/, cpuid.o interrupt.o kvm.o kvm-cpu.o bios.o irq.o bios/bios-rom.o)
OBJS := $(addprefix $(BUILD)/, $(OBJS))

$(shell mkdir -p $(BUILD)/{x86/bios,util,disk,virtio,hw})

$(BUILD)/%.o: %.c
	@echo "  CC     " $@
	@ $(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $< -o $@

$(BUILD)/%.o: %.S
	@echo "  AS     " $@
	@ $(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $< -o $@

all: lkvm lkvm-s

lkvm: $(OBJS)
	@echo "  LD     " $@
	@ ld -nostdlib -L/usr/x86_64-linux-musl/lib64 -lc -lpthread -rpath /usr/x86_64-linux-musl/lib64/ \
		-dynamic-linker /lib/ld-musl-x86_64.so.1 /usr/x86_64-linux-musl/lib64/crt1.o $^ -o $@
	@ sudo setcap cap_net_admin+ep $@

lkvm-s: $(OBJS)
	@echo "  LD     " $@
	@ ld /usr/x86_64-linux-musl/lib64/crt1.o $^ /usr/x86_64-linux-musl/lib64/libc.a -o $@
	@ sudo setcap cap_net_admin+ep $@

BIOS := $(addprefix $(BUILD)/x86/bios/, e820.o int15.o entry.o)
$(BIOS): EXTRA_CFLAGS := -m16

x86/bios/bios.bin.elf: $(BIOS)
	@echo "  LD     " $@
	@ ld -T x86/bios/rom.ld.S -o $@ $^

x86/bios/bios.bin: x86/bios/bios.bin.elf
	@echo "  OBJCOPY" $@
	@ objcopy -O binary -j .text $< $@

x86/bios/bios-rom.h: x86/bios/bios.bin.elf
	@echo "  NM     " $@
	@ cd x86/bios && sh gen-offsets.sh > bios-rom.h

$(BUILD)/x86/bios.o: x86/bios/bios.bin x86/bios/bios-rom.h

$(BUILD)/x86/bios/bios-rom.o: x86/bios/bios.bin

clean:
	rm -rf x86/bios/{bios.bin.elf,bios.bin,bios-rom.h} lkvm $(BUILD)
