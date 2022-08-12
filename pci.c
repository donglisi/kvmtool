#include "kvm/devices.h"
#include "kvm/pci.h"
#include "kvm/ioport.h"
#include "kvm/irq.h"
#include "kvm/util.h"
#include "kvm/kvm.h"

#include <linux/err.h>
#include <assert.h>

static u32 pci_config_address_bits;

/* This is within our PCI gap - in an unused area.
 * Note this is a PCI *bus address*, is used to assign BARs etc.!
 * (That's why it can still 32bit even with 64bit guests-- 64bit
 * PCI isn't currently supported.)
 */
static u32 mmio_blocks			= KVM_PCI_MMIO_AREA;

/*
 * BARs must be naturally aligned, so enforce this in the allocator.
 */
u32 pci_get_mmio_block(u32 size)
{
	u32 block = ALIGN(mmio_blocks, size);
	mmio_blocks = block + size;
	return block;
}

static bool pci_bar_is_implemented(struct pci_device_header *pci_hdr, int bar_num)
{
	return pci__bar_size(pci_hdr, bar_num);
}

static bool pci_bar_is_active(struct pci_device_header *pci_hdr, int bar_num)
{
	return  pci_hdr->bar_active[bar_num];
}

static void *pci_config_address_ptr(u16 port)
{
	unsigned long offset;
	void *base;

	offset	= port - PCI_CONFIG_ADDRESS;
	base	= &pci_config_address_bits;

	return base + offset;
}

static void pci_config_address_mmio(struct kvm_cpu *vcpu, u64 addr, u8 *data,
				    u32 len, u8 is_write, void *ptr)
{
	void *p = pci_config_address_ptr(addr);

	if (is_write)
		memcpy(p, data, len);
	else
		memcpy(data, p, len);
}
static bool pci_device_exists(u8 bus_number, u8 device_number, u8 function_number)
{
	union pci_config_address pci_config_address;

	pci_config_address.w = ioport__read32(&pci_config_address_bits);

	if (pci_config_address.bus_number != bus_number)
		return false;

	if (pci_config_address.function_number != function_number)
		return false;

	return !IS_ERR_OR_NULL(device__find_dev(DEVICE_BUS_PCI, device_number));
}

static void pci_config_data_mmio(struct kvm_cpu *vcpu, u64 addr, u8 *data,
				 u32 len, u8 is_write, void *kvm)
{
	union pci_config_address pci_config_address;

	if (len > 4)
		len = 4;

	pci_config_address.w = ioport__read32(&pci_config_address_bits);
	/*
	 * If someone accesses PCI configuration space offsets that are not
	 * aligned to 4 bytes, it uses ioports to signify that.
	 */
	pci_config_address.reg_offset = addr - PCI_CONFIG_DATA;

	if (is_write)
		pci__config_wr(vcpu->kvm, pci_config_address, data, len);
	else
		pci__config_rd(vcpu->kvm, pci_config_address, data, len);
}

static int pci_activate_bar(struct kvm *kvm, struct pci_device_header *pci_hdr,
			    int bar_num)
{
	int r = 0;

	if (pci_bar_is_active(pci_hdr, bar_num))
		goto out;

	r = pci_hdr->bar_activate_fn(kvm, pci_hdr, bar_num, pci_hdr->data);
	if (r < 0) {
		pci_dev_warn(pci_hdr, "Error activating emulation for BAR %d",
			     bar_num);
		goto out;
	}
	pci_hdr->bar_active[bar_num] = true;

out:
	return r;
}

static int pci_deactivate_bar(struct kvm *kvm, struct pci_device_header *pci_hdr,
			      int bar_num)
{
	int r = 0;

	if (!pci_bar_is_active(pci_hdr, bar_num))
		goto out;

	r = pci_hdr->bar_deactivate_fn(kvm, pci_hdr, bar_num, pci_hdr->data);
	if (r < 0) {
		pci_dev_warn(pci_hdr, "Error deactivating emulation for BAR %d",
			     bar_num);
		goto out;
	}
	pci_hdr->bar_active[bar_num] = false;

out:
	return r;
}

static void pci_config_bar_wr(struct kvm *kvm,
			      struct pci_device_header *pci_hdr, int bar_num,
			      u32 value)
{
	u32 old_addr, new_addr, bar_size;
	u32 mask;
	int r;

	if (pci__bar_is_io(pci_hdr, bar_num))
		mask = (u32)PCI_BASE_ADDRESS_IO_MASK;
	else
		mask = (u32)PCI_BASE_ADDRESS_MEM_MASK;

	/*
	 * If the kernel masks the BAR, it will expect to find the size of the
	 * BAR there next time it reads from it. After the kernel reads the
	 * size, it will write the address back.
	 *
	 * According to the PCI local bus specification REV 3.0: The number of
	 * upper bits that a device actually implements depends on how much of
	 * the address space the device will respond to. A device that wants a 1
	 * MB memory address space (using a 32-bit base address register) would
	 * build the top 12 bits of the address register, hardwiring the other
	 * bits to 0.
	 *
	 * Furthermore, software can determine how much address space the device
	 * requires by writing a value of all 1's to the register and then
	 * reading the value back. The device will return 0's in all don't-care
	 * address bits, effectively specifying the address space required.
	 *
	 * Software computes the size of the address space with the formula
	 * S =  ~B + 1, where S is the memory size and B is the value read from
	 * the BAR. This means that the BAR value that kvmtool should return is
	 * B = ~(S - 1).
	 */
	if (value == 0xffffffff) {
		value = ~(pci__bar_size(pci_hdr, bar_num) - 1);
		/* Preserve the special bits. */
		value = (value & mask) | (pci_hdr->bar[bar_num] & ~mask);
		pci_hdr->bar[bar_num] = value;
		return;
	}

	value = (value & mask) | (pci_hdr->bar[bar_num] & ~mask);

	/* Don't toggle emulation when region type access is disbled. */
	if (pci__bar_is_io(pci_hdr, bar_num) &&
	    !pci__io_space_enabled(pci_hdr)) {
		pci_hdr->bar[bar_num] = value;
		return;
	}

	if (pci__bar_is_memory(pci_hdr, bar_num) &&
	    !pci__memory_space_enabled(pci_hdr)) {
		pci_hdr->bar[bar_num] = value;
		return;
	}

	/*
	 * BAR reassignment can be done while device access is enabled and
	 * memory regions for different devices can overlap as long as no access
	 * is made to the overlapping memory regions. To implement BAR
	 * reasignment, we deactivate emulation for the region described by the
	 * BAR value that the guest is changing, we disable emulation for the
	 * regions that overlap with the new one (by scanning through all PCI
	 * devices), we enable emulation for the new BAR value and finally we
	 * enable emulation for all device regions that were overlapping with
	 * the old value.
	 */
	old_addr = pci__bar_address(pci_hdr, bar_num);
	new_addr = __pci__bar_address(value);
	bar_size = pci__bar_size(pci_hdr, bar_num);

	r = pci_deactivate_bar(kvm, pci_hdr, bar_num);
	if (r < 0)
		return;

	pci_hdr->bar[bar_num] = value;
	r = pci_activate_bar(kvm, pci_hdr, bar_num);
}

void pci__config_wr(struct kvm *kvm, union pci_config_address addr, void *data, int size)
{
	void *base;
	u8 bar;
	u16 offset;
	struct pci_device_header *pci_hdr;
	u8 dev_num = addr.device_number;
	u32 value = 0;

	if (!pci_device_exists(addr.bus_number, dev_num, 0))
		return;

	offset = addr.w & PCI_DEV_CFG_MASK;
	base = pci_hdr = device__find_dev(DEVICE_BUS_PCI, dev_num)->data;

	if (pci_hdr->cfg_ops.write)
		pci_hdr->cfg_ops.write(kvm, pci_hdr, offset, data, size);

	/*
	 * legacy hack: ignore writes to uninitialized regions (e.g. ROM BAR).
	 * Not very nice but has been working so far.
	 */
	if (*(u32 *)(base + offset) == 0)
		return;

	bar = (offset - PCI_BAR_OFFSET(0)) / sizeof(u32);
	if (bar < 6) {
		memcpy(&value, data, size);
		pci_config_bar_wr(kvm, pci_hdr, bar, value);
		return;
	}

	memcpy(base + offset, data, size);
}

void pci__config_rd(struct kvm *kvm, union pci_config_address addr, void *data, int size)
{
	u16 offset;
	struct pci_device_header *pci_hdr;
	u8 dev_num = addr.device_number;

	if (pci_device_exists(addr.bus_number, dev_num, 0)) {
		pci_hdr = device__find_dev(DEVICE_BUS_PCI, dev_num)->data;
		offset = addr.w & PCI_DEV_CFG_MASK;

		if (pci_hdr->cfg_ops.read)
			pci_hdr->cfg_ops.read(kvm, pci_hdr, offset, data, size);

		memcpy(data, (void *)pci_hdr + offset, size);
	} else {
		memset(data, 0xff, size);
	}
}

struct pci_device_header *pci__find_dev(u8 dev_num)
{
	struct device_header *hdr = device__find_dev(DEVICE_BUS_PCI, dev_num);

	if (IS_ERR_OR_NULL(hdr))
		return NULL;

	return hdr->data;
}

int pci__register_bar_regions(struct kvm *kvm, struct pci_device_header *pci_hdr,
			      bar_activate_fn_t bar_activate_fn,
			      bar_deactivate_fn_t bar_deactivate_fn, void *data)
{
	int i, r;

	assert(bar_activate_fn && bar_deactivate_fn);

	pci_hdr->bar_activate_fn = bar_activate_fn;
	pci_hdr->bar_deactivate_fn = bar_deactivate_fn;
	pci_hdr->data = data;

	for (i = 0; i < 6; i++) {
		if (!pci_bar_is_implemented(pci_hdr, i))
			continue;

		assert(!pci_bar_is_active(pci_hdr, i));

		if (pci__bar_is_io(pci_hdr, i) &&
		    pci__io_space_enabled(pci_hdr)) {
			r = pci_activate_bar(kvm, pci_hdr, i);
			if (r < 0)
				return r;
		}

		if (pci__bar_is_memory(pci_hdr, i) &&
		    pci__memory_space_enabled(pci_hdr)) {
			r = pci_activate_bar(kvm, pci_hdr, i);
			if (r < 0)
				return r;
		}
	}

	return 0;
}

int pci__init(struct kvm *kvm)
{
	int r;

	r = kvm__register_pio(kvm, PCI_CONFIG_DATA, 4,
				 pci_config_data_mmio, NULL);
	if (r < 0)
		return r;
	r = kvm__register_pio(kvm, PCI_CONFIG_ADDRESS, 4,
				 pci_config_address_mmio, NULL);
	if (r < 0)
		goto err_unregister_data;


	return 0;

err_unregister_addr:
	kvm__deregister_pio(kvm, PCI_CONFIG_ADDRESS);
err_unregister_data:
	kvm__deregister_pio(kvm, PCI_CONFIG_DATA);
	return r;
}
dev_base_init(pci__init);

int pci__exit(struct kvm *kvm)
{
	kvm__deregister_pio(kvm, PCI_CONFIG_DATA);
	kvm__deregister_pio(kvm, PCI_CONFIG_ADDRESS);

	return 0;
}
dev_base_exit(pci__exit);
