/*  riscv64-linux.elf-fold.S -- linkage to C code to process Elf binary
*
*  This file is part of the UPX executable compressor.
*
*  Copyright (C) 2000-2025 John F. Reiser
*  All Rights Reserved.
*
*  UPX and the UCL library are free software; you can redistribute them
*  and/or modify them under the terms of the GNU General Public License as
*  published by the Free Software Foundation; either version 2 of
*  the License, or (at your option) any later version.
*
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with this program; see the file COPYING.
*  If not, write to the Free Software Foundation, Inc.,
*  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*
*  Markus F.X.J. Oberhumer              Laszlo Molnar
*  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
*
*  John F. Reiser
*  <jreiser@users.sourceforge.net>
*/

NBPW= 8
#include "arch/riscv/64/macros.S"
#include "arch/riscv/64/regs.h"

PATH_MAX= 4096  // /usr/include/linux/limits.h

sz_b_info= 12
  sz_unc= 0
  sz_cpr= 4

sz_l_info= 12
sz_p_info= 12

MAP_PRIVATE=   0x02
MAP_FIXED=     0x10

PROT_READ=     0x1

O_RDONLY=       0
FD_CWD= -100

OVERHEAD=2048

/* 64-bit mode only! */
__NR_read=  0
__NR_write= 1
__NR_openat=  2  //NYI
__NR_close= 3

__NR_mmap=      9
__NR_mprotect= 10
__NR_munmap=   11
__NR_msync=    26  // 0x1a
  MS_SYNC= 4
__NR_brk=      12
__NR_memfd_create= 0x13f  // 319
__NR_ftruncate= 0x4d  // 77

__NR_exit= 60
__NR_readlink= 89

unmap_all_pages= (1<<1)
is_ptinterp=     (1<<0)

// same as in riscv64-linux.elf-entry.S
F_FRAME= 8*NBPW
F_EOF=  7*NBPW  // sometimes omitted from FRAME
F_ENTR= 6*NBPW; F_PMASK= F_ENTR
F_RDX=  5*NBPW
F_LENU= 4*NBPW
F_ADRU= 3*NBPW
F_ELFA= 2*NBPW
F_LENX= 1*NBPW
F_ADRX= 0*NBPW

D_FOLD=  2*NBPW  // .data space at start of unfold
D_PMASK= 0*NBPW
D_XSIGSEGV= 1*NBPW

#define rsp sp  /* x2 */
#define rax a0  /* x10 */
#define rbx s1  /* x9 */
#define rbp s0  /* x8 */
#define rcx t2  /* x7 */
#define rdx t1  /* x6 */
#define r12 t0  /* x5 */

#define rdi a5  /* x15 */
#define rsi a4  /* x14 */
#define r15 a3  /* x13 */
#define r14 a2  /* x12 */
#define r13 a1  /* x11 */

#define rfd rbp  /* file descriptor for /proc/self/exe */

        .balign 8
PAGE_MASK: .quad -1<<12  // default
cancel_sigsegv: .quad 0  // subroutine that cancels sigaction(SIGSEGV,)

// IN: [ADRX,+LENX): compressed data; [ADRU,+LENU): expanded fold (w/ upx_main2)
// %rsp= %rbp= &F_ADRX; %r13= O_BINFO | is_ptinterp | unmap_all_pages

// no 'section', thus '.text'; also loaded first in riscv64-linux.elf-fold.bin.
// Code from riscv64-linux2.elf-main.c is also .text, and is next.
fold_begin:
////    ebreak  # DEBUG
// copy is_interp bit from r13 to F_ELFA(rbp)
	ld t0,F_ELFA(rbp); andi t1,r13,is_ptinterp; or t0,t0,t1;
	sd t0,F_ELFA(rbp)
// if !unmap_all_pages then need space on stack for result of readlink("/proc/self/exe",...)
        mv rsi,rsp
	  andi t0,r13,unmap_all_pages
	  bnez t0,5f; li t0,PATH_MAX; sub rsp,rsp,t0; 0:
        mv rdi,rsp
	li rcx,8
0:  // copy down  ADRX,LDRX,ELFA,ADRU,LENU,rdx,%entry,argc
	ld t0,(rsi); addi rsi,rsi,NBPW; addi rcx,rcx,-1
	sd t0,(rdi); addi rdi,rdi,NBPW; bnez rcx,0b

5:
0:  // copy down argv
	ld t0,(rsi); addi rsi,rsi,NBPW
	sd t0,(rdi); addi rdi,rdi,NBPW
	bnez t0,0b
	mv r14,rdi  // remember &new_env[0]

	andi t0,r13,unmap_all_pages; bnez t0,0f
	sd zero,(rdi); addi rdi,rdi,NBPW  // space for new_env[0]
0:  // find old Elf64_auxv
	ld t0,(rsi); sd t0,(rdi); bnez t0,0b
        mv t2,rdi  # &old Elf64_auxv

0:  // find &strings (beyond auxv)
	ld t0,(rsi); ld t1,NBPW(rsi); addi rsi,rsi,2*NBPW
	sd t0,(rdi); sd t1,NBPW(rdi); addi rdi,rdi,2*NBPW
	bnez t0,0b
        mv r15,rdi  # beyond auxv
        mv r13,rsi  # beginning of strings
        sub rdi,rdi,t2  # -length of auxv

	andi t0,r13,unmap_all_pages; beqz t0,env_pse
        ori rfd,rfd,~0; mv r14,rdi;   j   no_env_pse  # no fd; beyond auxv
env_pse:
	li arg3,0  # O_RdONLY
	lla arg2,proc_self_exe
	li arg1,FD_CWD
        call openat; mv rfd,rv  # fd

        li arg3,-1+ PATH_MAX  # buflen
	mv arg2,sp  # buffer
	lla arg1,proc_self_exe
	syscall __NR_readlink; bgez rv,0f
// readlink() failed. Set the result equal to the argument.
        lla arg2,proc_self_exe  # failure result= "/proc/self/exe"
	li rcx,15  # sizeof "/proc/self/exe"
0:
  // std
        addi rdi,r13,-1  # dst last byte
	sb zero,(rdi)  # terminate
        addi rsi,arg2,-1
	add rsi,rsi,rcx  # src last byte
0:  // slide up (hi end goes first)
	lbu t0,(rsi); addi rsi,rsi,-1; addi rcx,rcx,-1
	sb  t0,(rdi); addi rdi,rdi,-1; bnez rcx,0b
// add new env "   =..."
	li t0,' '; sb t0,-3(rdi); sb t0,-2(rdi); sb t0,-1(rdi); addi rdi,rdi,-3
        sd rdi,(r14)  # new_env[0]
        andi rdi,rdi,-NBPW  # align
        mv rcx,r15
        sub rsp,rsp,rcx  # byte count

        addi rdi,rdi,-NBPW   # &last qword of new auxv
	addi rsi,r15,-NBPW   # &last qword of old auxv

        // end of auxv must move by even number of NBPW
        mv t0,rdi
        xor t0,t0,rsi
        andi t0,t0,NBPW
        sub rdi,rdi,t0
        mv r14,rdi  # &last qword of new auxv

	srl rcx,rcx,3
0:
	ld t0,(rsi); addi rsi,rsi,-NBPW; addi rcx,rcx,-1
	sd t0,(rdi); addi rdi,rdi,-NBPW; bnez rcx,0b
        addi rsp,rdi,NBPW
  // cld

        add arg4,r14,r12; addi arg4,arg4,NBPW  # &new Elf64_auxv  %r12 dead
no_env_pse:
	ld arg1,F_ADRX(rbp)
	ld arg2,F_LENX(rbp)
        andi arg1,arg1,~(is_ptinterp | unmap_all_pages)

        ld arg5,F_ELFA(rbp)  # ELFA | is_ptinterp
	andi t0,arg5,is_ptinterp; or arg4,arg4,t0  # transfer is_ptinterp to &new_ELF64_auxv
        sub arg5,arg5,t0  # and clear from  ELFA
        mv  r13,arg5  # save ELFA
        addi rsp,rsp,-OVERHEAD
        mv arg3,rsp  # &ELf64_Ehdr temporary space
        call upx_main2  # Out: rv= entry

// entry= upx_main2(
// b_info *arg1,       {%rdi}
// total_size arg2,    {%rsi}
// Elf64_Ehdr *arg3,   {%rdx}
// Elf32_Auxv_t *arg4, {%rcx}
// Elf64_Addr elfaddr  {%r8}
// )

// rsp/ {OVERHEAD},ADRU,LENU,rdx,%entry,  argc,argv,0,envp,0,auxv,0,strings
	li t0,OVERHEAD
        add rsp,rsp,t0  # remove Elf64_Ehdr temporary space
#define r_fd  ebx
        ld rfd,(rbp)  //NYI
        sd rv,3*NBPW(rsp)  # entry

        //NYI call *cancel_sigsegv(%rip)

sz_Ehdr= 8*NBPW
e_type= 16
ET_EXEC= 2
sz_Phdr= 7*NBPW
p_memsz= 5*NBPW
// Discard pages of compressed data (includes [ADRX,+LENX) )
        addi arg2,r13,p_memsz+sz_Phdr+sz_Ehdr  #   Phdr[C_TEXT= 1].p_memsz
        //cmpw $ET_EXEC, e_type(%r13); jne 1f
        mv arg1,r13; call brk  // also sets the brk
1:
        mv arg1,r13; call munmap  # discard C_TEXT compressed data

// Map 1 page of /proc/self/exe so that the symlink does not disappear.
	bltz rfd,no_pse_map
        li arg6,0  # 0 offset
        mv arg5,rfd
        li arg4,MAP_PRIVATE
        li arg3,PROT_READ
        li arg2,1<<12
        li arg1,0
        call mmap

        mv arg1,rfd
        call close

no_pse_map:
	ld arg1,F_ADRU(rbp)  # ADRU: unfolded upx_main2 etc.
        ld arg2,F_LENU(rbp)
        li a7,__NR_munmap
        jr r14  # goto: syscall; pop %rdx; ret

get_page_mask: .globl get_page_mask
        ld rv,PAGE_MASK
        ret

        section SYSCALLS
my_bkpt: .globl my_bkpt
        ebreak  // my_bkpt
        ret

proc_self_exe:
        .asciz "/proc/self/exe"
	.balign 4

upxfd_create: .globl upxfd_create // (char *tag, unsigned flags)
0: // try memfd_create
        syscall __NR_memfd_create; j ok_memfd  //NYI
O_RDWR= 2
O_DIRECTORY= 0200000  // 0x010000
O_TMPFILE= 020000000  // 0x400000
	li arg4,0700  # mode
	li arg3,O_RDWR|O_DIRECTORY|O_TMPFILE
	la arg3,dev_shm
	li arg1,FD_CWD
	syscall __NR_openat
ok_memfd:
        ret

Pmap: .globl Pmap  // page-align the lo end
        ld t0,PAGE_MASK; xori t0,t0,~0  // frag mask
        and arg1,arg1,t0  // frag
        sub arg1,arg1,t0
        add arg2,arg2,t0
mmap: .globl mmap
        li a7,__NR_mmap
sysgo:
sys_check:
	ebreak  // sys_check
        syscall 0 //NYI
//NYI syscall error checking
        ret

Psync: .globl Psync
        li a7,__NR_msync
	j 5f

Pprotect: .globl Pprotect
	li a7,__NR_mprotect
	j 5f

Punmap: .globl Punmap  // page-align the lo end
	li a7,__NR_munmap
5:
        ld t0,PAGE_MASK; xori t0,t0,~0  // frag mask
        and t0,t0,arg1  // frag
        sub arg1,arg1,t0
        add arg2,arg2,t0
	j sysgo

munmap: .globl munmap
        li a7,__NR_munmap; 5: j 5f
exit: .globl exit
        li a7,__NR_exit; 5: j 5f
brk: .globl brk
        li a7,__NR_brk; 5: j 5f
close: .globl close
        li a7,__NR_close; 5: j 5f
ftruncate: .globl ftruncate
        li a7,__NR_ftruncate; 5: j 5f
open: .globl openat
        li a7,__NR_openat; 5: j 5f
mprotect: .globl mprotect
        li a7,__NR_mprotect; 5: j 5f
msync: .globl msync
        li a7,__NR_msync; 5: j 5f
Pwrite: .globl Pwrite
write: .globl write
        li a7,__NR_write; 5: j 5f
read: .globl read
        li a7,__NR_read; 5: j sysgo

// vim:set ts=8 sw=8 et:
