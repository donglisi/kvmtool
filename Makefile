DEFINES	+= -D_GNU_SOURCE
DEFINES	+= -DKVMTOOLS_VERSION='"1.0"'
DEFINES	+= -DBUILD_ARCH='"x86"'

CC	:= gcc
CFLAGS	:= -Iinclude -Ix86/include $(DEFINES) -w

PROGRAM	:= lkvm
BUILD	:= build

OBJS	:=
OBJS	+= $(BUILD)/devices.o
OBJS	+= $(BUILD)/disk/core.o
OBJS	+= $(BUILD)/disk/qcow.o
OBJS	+= $(BUILD)/hw/serial.o
OBJS	+= $(BUILD)/hw/rtc.o
OBJS	+= $(BUILD)/irq.o
OBJS	+= $(BUILD)/kvm-cpu.o
OBJS	+= $(BUILD)/kvm.o
OBJS	+= $(BUILD)/kvm-ipc.o
OBJS	+= $(BUILD)/main.o
OBJS	+= $(BUILD)/builtin-balloon.o
OBJS	+= $(BUILD)/builtin-debug.o
OBJS	+= $(BUILD)/builtin-help.o
OBJS	+= $(BUILD)/builtin-list.o
OBJS	+= $(BUILD)/builtin-stat.o
OBJS	+= $(BUILD)/builtin-pause.o
OBJS	+= $(BUILD)/builtin-resume.o
OBJS	+= $(BUILD)/builtin-run.o
OBJS	+= $(BUILD)/builtin-setup.o
OBJS	+= $(BUILD)/builtin-stop.o
OBJS	+= $(BUILD)/builtin-version.o
OBJS	+= $(BUILD)/builtin-sandbox.o
OBJS	+= $(BUILD)/kvm-cmd.o
OBJS	+= $(BUILD)/mmio.o
OBJS	+= $(BUILD)/pci.o
OBJS	+= $(BUILD)/term.o
OBJS	+= $(BUILD)/guest_compat.o
OBJS	+= $(BUILD)/virtio/blk.o
OBJS	+= $(BUILD)/virtio/core.o
OBJS	+= $(BUILD)/virtio/net.o
OBJS	+= $(BUILD)/virtio/mmio.o
OBJS	+= $(BUILD)/virtio/pci.o
OBJS	+= $(BUILD)/virtio/9p.o
OBJS	+= $(BUILD)/virtio/9p-pdu.o
OBJS	+= $(BUILD)/virtio/console.o
OBJS	+= $(BUILD)/disk/blk.o
OBJS	+= $(BUILD)/disk/raw.o
OBJS	+= $(BUILD)/ioeventfd.o
OBJS	+= $(BUILD)/net/uip/core.o
OBJS	+= $(BUILD)/net/uip/arp.o
OBJS	+= $(BUILD)/net/uip/icmp.o
OBJS	+= $(BUILD)/net/uip/ipv4.o
OBJS	+= $(BUILD)/net/uip/tcp.o
OBJS	+= $(BUILD)/net/uip/udp.o
OBJS	+= $(BUILD)/net/uip/buf.o
OBJS	+= $(BUILD)/net/uip/csum.o
OBJS	+= $(BUILD)/net/uip/dhcp.o
OBJS	+= $(BUILD)/util/init.o
OBJS	+= $(BUILD)/util/threadpool.o
OBJS	+= $(BUILD)/util/parse-options.o
OBJS	+= $(BUILD)/util/iovec.o
OBJS	+= $(BUILD)/util/rbtree.o
OBJS	+= $(BUILD)/util/rbtree-interval.o
OBJS	+= $(BUILD)/util/strbuf.o
OBJS	+= $(BUILD)/util/read-write.o
OBJS	+= $(BUILD)/util/util.o
OBJS	+= $(BUILD)/vfio/core.o
OBJS	+= $(BUILD)/vfio/pci.o
OBJS	+= $(BUILD)/x86/boot.o
OBJS	+= $(BUILD)/x86/ioport.o
OBJS	+= $(BUILD)/x86/cpuid.o
OBJS	+= $(BUILD)/x86/mptable.o
OBJS	+= $(BUILD)/x86/interrupt.o
OBJS	+= $(BUILD)/x86/kvm.o
OBJS	+= $(BUILD)/x86/kvm-cpu.o
OBJS	+= $(BUILD)/x86/bios.o
OBJS	+= $(BUILD)/x86/bios/bios-rom.o

$(BUILD)/%.o: %.c
	@ mkdir -p build/{x86/bios,net/uip,util,disk,virtio,hw,vfio}
	$(CC) -c $(CFLAGS) $< -o $@

all: $(PROGRAM)

$(PROGRAM): $(OBJS)
	$(CC) $^ -o $@

x86/bios/bios.bin.elf:
	$(CC) $(CFLAGS) -m16 -c x86/bios/e820.c -o $(BUILD)/x86/bios/e820.o
	$(CC) $(CFLAGS) -m16 -c x86/bios/memcpy.c -o $(BUILD)/x86/bios/memcpy.o
	$(CC) $(CFLAGS) -m16 -c x86/bios/int10.c -o $(BUILD)/x86/bios/int10.o
	$(CC) $(CFLAGS) -m16 -c x86/bios/int15.c -o $(BUILD)/x86/bios/int15.o
	$(CC) $(CFLAGS) -m16 -c x86/bios/entry.S -o $(BUILD)/x86/bios/entry.o
	ld -T x86/bios/rom.ld.S -o $@ $(BUILD)/x86/bios/e820.o $(BUILD)/x86/bios/memcpy.o \
		$(BUILD)/x86/bios/int10.o $(BUILD)/x86/bios/int15.o $(BUILD)/x86/bios/entry.o

x86/bios/bios.bin: x86/bios/bios.bin.elf
	objcopy -O binary -j .text $< $@

x86/bios/bios-rom.h: x86/bios/bios.bin.elf
	cd x86/bios && sh gen-offsets.sh > bios-rom.h

$(BUILD)/x86/bios.o: x86/bios/bios.bin x86/bios/bios-rom.h

$(BUILD)/x86/bios/bios-rom.o: x86/bios/bios.bin
	$(CC) -c $(CFLAGS) x86/bios/bios-rom.S -o $@

clean:
	rm -f x86/bios/{bios.bin.elf,bios.bin,bios-rom.h}
	rm -rf build lkvm
.PHONY: clean
