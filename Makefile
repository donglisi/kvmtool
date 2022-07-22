DEFINES	:= -D_GNU_SOURCE -DKVMTOOLS_VERSION='"1.0"' -DBUILD_ARCH='"x86"'
CC	:= gcc
CFLAGS	:= -nostdinc -I/usr/x86_64-linux-musl/include/ -Iinclude -Ix86/include $(DEFINES)
BUILD	:= build

OBJS := devices.o irq.o kvm-cpu.o kvm.o main.o builtin-run.o kvm-cmd.o mmio.o pci.o term.o ioeventfd.o
OBJS += $(addprefix disk/, core.o raw.o)
OBJS += $(addprefix hw/, serial.o rtc.o)
OBJS += $(addprefix virtio/, blk.o core.o net.o pci.o console.o)
OBJS += $(addprefix net/uip/, core.o arp.o icmp.o ipv4.o tcp.o udp.o buf.o csum.o dhcp.o)
OBJS += $(addprefix util/, init.o threadpool.o parse-options.o iovec.o rbtree.o rbtree-interval.o strbuf.o read-write.o util.o)
OBJS += $(addprefix x86/, boot.o cpuid.o mptable.o interrupt.o kvm.o kvm-cpu.o bios.o)
OBJS += x86/bios/bios-rom.o
OBJS := $(addprefix $(BUILD)/, $(OBJS))

$(shell mkdir -p $(BUILD)/{x86/bios,net/uip,util,disk,virtio,hw})

$(BUILD)/%.o: %.c
	$(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $< -o $@

$(BUILD)/%.o: %.S
	$(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $< -o $@

all: lkvm

lkvm: $(OBJS)
	ld -nostdlib -L/usr/x86_64-linux-musl/lib64 -lc -lpthread \
		-rpath /usr/x86_64-linux-musl/lib64/ \
		-dynamic-linker /lib/ld-musl-x86_64.so.1 \
		/usr/x86_64-linux-musl/lib64/crt1.o $^ -o $@
	sudo setcap cap_net_admin+ep $@

lkvm-s: $(OBJS)
	ld /usr/x86_64-linux-musl/lib64/crt1.o $^ /usr/x86_64-linux-musl/lib64/libc.a -o $@
	sudo setcap cap_net_admin+ep $@

BIOS := $(addprefix $(BUILD)/x86/bios/, e820.o int15.o entry.o)
$(BIOS): EXTRA_CFLAGS := -m16

x86/bios/bios.bin.elf: $(BIOS)
	ld -T x86/bios/rom.ld.S -o $@ $^

x86/bios/bios.bin: x86/bios/bios.bin.elf
	objcopy -O binary -j .text $< $@

x86/bios/bios-rom.h: x86/bios/bios.bin.elf
	cd x86/bios && sh gen-offsets.sh > bios-rom.h

$(BUILD)/x86/bios.o: x86/bios/bios.bin x86/bios/bios-rom.h

$(BUILD)/x86/bios/bios-rom.o: x86/bios/bios.bin

clean:
	rm -rf x86/bios/{bios.bin.elf,bios.bin,bios-rom.h} lkvm $(BUILD)
