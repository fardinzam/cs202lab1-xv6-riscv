        #
        # low-level code to handle traps from user space into
        # the kernel, and returns from kernel to user.
        #
        # the kernel maps the page holding this code
        # at the same virtual address (TRAMPOLINE)
        # in user and kernel space so that it continues
        # to work when it switches page tables.
        # kernel.ld causes this code to start at 
        # a page boundary.
        #

#include "riscv.h"
#include "memlayout.h"

.section trampsec
.globl trampoline
.globl usertrap
trampoline:
.align 4
.globl uservec
uservec:    
	#
        # trap.c sets stvec to point here, so
        # traps from user space start here,
        # in supervisor mode, but with a
        # user page table.
        #

        # swap a0 and sscratch
        # sscratch contains either:
        #   - user a0 (on first trap, or if not set by prepare_return)
        #   - trapframe address (set by prepare_return for threads)
        csrrw a0, sscratch, a0
        
        # Check if a0 (from original sscratch) is a valid trapframe address
        # Valid range: TRAPFRAME - 20*PGSIZE to TRAPFRAME (for up to 20 threads)
        # Note: We use t0, t1, and t2 as temporaries here, losing user's t0, t1, t2 values.
        # This is acceptable as t0, t1, and t2 are temporary registers.
        # First check if a0 is null or very small (safety check)
        beqz a0, use_default  # if a0 is 0, use default
        # Check if address is page-aligned (must be multiple of PGSIZE)
        li t0, 4095  # PGSIZE - 1
        and t0, a0, t0  # t0 = a0 & (PGSIZE - 1)
        bnez t0, use_default  # if not page-aligned, use default
        # Check if in valid range
        li t1, TRAPFRAME
        li t2, TRAPFRAME - 81920  # 20*4096 = 81920
        blt a0, t2, use_default  # if a0 < TRAPFRAME-20*PGSIZE, use default
        bge a0, t1, use_default  # if a0 >= TRAPFRAME, use default
        # a0 contains valid trapframe address, use it
        j save_registers
        
use_default:
        # Use default TRAPFRAME address
        li a0, TRAPFRAME
        
save_registers:
        # a0 now contains the trapframe address (validated or default)
        # Save the user a0 (now in sscratch) to trapframe->a0
        csrr t0, sscratch  # get user a0 from sscratch (t0 is now temp)
        sd t0, 112(a0)  # save user a0 to trapframe->a0
        
        # save the user registers in TRAPFRAME
        sd ra, 40(a0)
        sd sp, 48(a0)
        sd gp, 56(a0)
        sd tp, 64(a0)
        # t0, t1, t2 lost as temporaries (acceptable for temp registers)
        sd t0, 72(a0)  # save what t0 currently holds (user a0, but we already saved that)
        sd t1, 80(a0)  # save what t1 currently holds (TRAPFRAME or comparison value)
        sd t2, 88(a0)  # save what t2 currently holds (TRAPFRAME-81920 or comparison value)
        sd s0, 96(a0)
        sd s1, 104(a0)
        sd a1, 120(a0)
        sd a2, 128(a0)
        sd a3, 136(a0)
        sd a4, 144(a0)
        sd a5, 152(a0)
        sd a6, 160(a0)
        sd a7, 168(a0)
        sd s2, 176(a0)
        sd s3, 184(a0)
        sd s4, 192(a0)
        sd s5, 200(a0)
        sd s6, 208(a0)
        sd s7, 216(a0)
        sd s8, 224(a0)
        sd s9, 232(a0)
        sd s10, 240(a0)
        sd s11, 248(a0)
        sd t3, 256(a0)
        sd t4, 264(a0)
        sd t5, 272(a0)
        sd t6, 280(a0)

	# user a0 already saved in trapframe->a0 above

        # initialize kernel stack pointer, from p->trapframe->kernel_sp
        # Double-check a0 is not null before accessing (safety check)
        beqz a0, use_default  # if a0 is somehow 0, use default
        ld sp, 8(a0)

        # make tp hold the current hartid, from p->trapframe->kernel_hartid
        ld tp, 32(a0)

        # load the address of usertrap(), from p->trapframe->kernel_trap
        ld t0, 16(a0)

        # fetch the kernel page table address, from p->trapframe->kernel_satp.
        ld t1, 0(a0)

        # Save trapframe address in sscratch before calling usertrap()
        # (a0 currently holds the trapframe address)
        # This ensures we have the correct trapframe address after usertrap returns
        # prepare_return() will also set sscratch, but we want to preserve our validated address
        csrw sscratch, a0

        # wait for any previous memory operations to complete, so that
        # they use the user page table.
        sfence.vma zero, zero

        # install the kernel page table.
        csrw satp, t1

        # flush now-stale user entries from the TLB.
        sfence.vma zero, zero

        # call usertrap()
        jalr t0
        
        # usertrap() returns satp in a0
        # We need to call userret with:
        #   a0 = trapframe address
        #   a1 = satp (return value from usertrap)
        # Save satp to a1 first
        mv a1, a0
        
        # Get trapframe address from sscratch (we saved it before calling usertrap,
        # and prepare_return() also sets it, so it should be correct)
        csrr a0, sscratch
        
        # Validate that a0 is in the valid range
        # If not, use default TRAPFRAME
        beqz a0, use_default_ret
        li t0, TRAPFRAME - 81920  # 20*4096 = 81920
        blt a0, t0, use_default_ret  # if a0 < TRAPFRAME-20*PGSIZE, use default
        li t0, TRAPFRAME
        bge a0, t0, use_default_ret  # if a0 >= TRAPFRAME, use default
        # a0 contains valid trapframe address, use it
        j call_userret
        
use_default_ret:
        # Use default TRAPFRAME address
        li a0, TRAPFRAME
        
call_userret:
        # Now a0 = trapframe address, a1 = satp
        # Jump to userret
        j userret

.globl userret
userret:
        # userret(trapframe_addr, satp)
        # a0: trapframe address in user page table
        # a1: user page table, for satp
        # return from kernel to user.

        # switch to the user page table.
        sfence.vma zero, zero
        csrw satp, a1
        sfence.vma zero, zero

        # a0 already contains the trapframe address

        # restore all but a0 from TRAPFRAME
        ld ra, 40(a0)
        ld sp, 48(a0)
        ld gp, 56(a0)
        ld tp, 64(a0)
        ld t0, 72(a0)
        ld t1, 80(a0)
        ld t2, 88(a0)
        ld s0, 96(a0)
        ld s1, 104(a0)
        ld a1, 120(a0)
        ld a2, 128(a0)
        ld a3, 136(a0)
        ld a4, 144(a0)
        ld a5, 152(a0)
        ld a6, 160(a0)
        ld a7, 168(a0)
        ld s2, 176(a0)
        ld s3, 184(a0)
        ld s4, 192(a0)
        ld s5, 200(a0)
        ld s6, 208(a0)
        ld s7, 216(a0)
        ld s8, 224(a0)
        ld s9, 232(a0)
        ld s10, 240(a0)
        ld s11, 248(a0)
        ld t3, 256(a0)
        ld t4, 264(a0)
        ld t5, 272(a0)
        ld t6, 280(a0)

	# restore user a0
        ld a0, 112(a0)
        
        # return to user mode and user pc.
        # prepare_return() already set sscratch to the trapframe address for the next trap.
        # usertrapret() set up sstatus and sepc.
        sret
