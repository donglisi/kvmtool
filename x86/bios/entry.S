/*
 * Our pretty trivial BIOS emulation
 */

#include <kvm/bios.h>
#include <kvm/assembly.h>

	.org 0
	.code16gcc

#define EFLAGS_CF	(1 << 0)

#include "macro.S"

/* If you change these macros, remember to update 'struct biosregs' */
.macro SAVE_BIOSREGS
	pushl	%fs
	pushl	%es
	pushl	%ds
	pushl	%edi
	pushl	%esi
	pushl	%ebp
	pushl	%esp
	pushl	%edx
	pushl	%ecx
	pushl	%ebx
	pushl	%eax
.endm

.macro RESTORE_BIOSREGS
	popl	%eax
	popl	%ebx
	popl	%ecx
	popl	%edx
	popl	%esp
	popl	%ebp
	popl	%esi
	popl	%edi
	popl	%ds
	popl	%es
	popl	%fs
.endm

/*
 * fake interrupt handler, nothing can be faster ever
 */
ENTRY(bios_intfake)
	/*
	 * Set CF to indicate failure. We don't want callers to think that the
	 * interrupt handler succeeded and then treat the return values in
	 * registers as valid data.
	 */
	orl	$EFLAGS_CF, 0x4(%esp)

	IRET
ENTRY_END(bios_intfake)

ENTRY(bios_int15)
	SAVE_BIOSREGS

	movl	%esp, %eax
	call	int15_handler

	RESTORE_BIOSREGS

	IRET
ENTRY_END(bios_int15)

GLOBAL(__locals)

#include "local.S"

END(__locals)

/*
 * Add this section to ensure final binary has a non-executable stack.
 */
.section .note.GNU-stack,"",@progbits
