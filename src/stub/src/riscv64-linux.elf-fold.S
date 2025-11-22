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
__NR_openat=  56
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
__NR_readlinkat= 78

unmap_all_pages= (1<<1)
is_ptinterp=     (1<<0)

// same as in riscv64-linux.elf-entry.S
F_FRAME= 8*NBPW
F_EOF=  7*NBPW  // used only by de-compressors
F_ENTR= 6*NBPW; F_PMASK= F_ENTR  // UNUSED
F_RDX=  5*NBPW  // UNUSED
F_LENU= 4*NBPW
F_ADRU= 3*NBPW
F_ELFA= 2*NBPW
F_LENX= 1*NBPW  # 4 bytes only
F_MFD=  1*NBPW + 4
F_ADRX= 0*NBPW

D_FOLD=  2*NBPW  // .data space at start of unfold
D_PMASK= 0*NBPW
D_XSIGSEGV= 1*NBPW

#define call jal

#define rdi a5  /* x15    arg6 */
#define rsi a4  /* x14    arg5 */
#define rcx a3  /* x13    arg4 */
#define ta  a2  /* x12    arg3 */
#define rdx a1  /* x11    arg2 */
#define rax a0  /* x10 rv arg1 */
#define r13 s1  /* x9 */
#define rbp s0  /* x8 fp */

#define r14 a6  /* x16 */
#define r15 a7  /* x17 */

// OVERLAPS
#define r12 ta  /* x12 */
#define tb  rcx /* x13 */

        //.balign 8
get_page_mask: .globl get_page_mask
L_get_page_mask:
        lui rv,0xfffff  // default 4K
        ret
        .int 0

cancel_sigsegv: .quad 0  // subroutine that cancels sigaction(SIGSEGV,)

// IN: [ADRX,+LENX): compressed data; [ADRU,+LENU): expanded fold (w/ upx_main2)
// %sp= %rbp= &F_ADRX; s4/ O_BINFO | is_ptinterp | unmap_all_pages

// no 'section', thus '.text'; also loaded first in riscv64-linux.elf-fold.bin.
// Code from riscv64-linux2.elf-main.c is also .text, and is next.
fold_begin:
	mv rbp,sp
        j 6f

Pprotect: .globl Pprotect
        li a7,__NR_mprotect
        j 3f

Punmap: .globl Punmap  // page-align the lo end
munmap: .global munmap
L_munmap:
        li a7,__NR_munmap
        j 3f

Pmap: .globl Pmap  // page-align the lo end
mmap: .globl mmap
L_mmap:
        li a7,__NR_mmap
3:
Palign:
        mv x5,ra; call L_get_page_mask; mv ra,x5  // rv= PAGE_MASK
        xori ta,rv,~0  // frag mask
        and arg1,arg1,ta  // frag
        sub arg1,arg1,ta
        add arg2,arg2,ta
        j sysgo

#define binf s4  /* x20 */
6: // (fold begin) copy is_interp bit from r13 to F_ELFA(rbp)
        lw r13,0(s4)
        ld ta,F_ELFA(rbp); andi tb,r13,is_ptinterp
	or ta,ta,tb;
        sd ta,F_ELFA(rbp)
// if !unmap_all_pages then need space on stack for result of readlinkat("/proc/self/exe",...)
        mv rsi,sp
          andi ta,r13,unmap_all_pages
          bnez ta,5f
	    li ta,2*NBPW + F_FRAME + PATH_MAX
	    sub sp,sp,ta
        mv rdi,sp
        li rcx,1+ F_FRAME/NBPW  # include argc
0:  // copy down  ADRX,LENX,ELFA,ADRU,LENU,rdx,%entry,eof,argc
        ld ta,(rsi); addi rsi,rsi,NBPW; addi rcx,rcx,-1
        sd ta,(rdi); addi rdi,rdi,NBPW; bnez rcx,0b
5:

0:  // copy down argv
        ld ta,(rsi); addi rsi,rsi,NBPW
        sd ta,(rdi); addi rdi,rdi,NBPW
        bnez ta,0b
        mv r14,rdi  // remember &new_env[0]

        andi ta,r13,unmap_all_pages; bnez ta,0f
        sd zero,(rdi); addi rdi,rdi,NBPW  // space for new_env[0]
0:  // find old Elf64_auxv (beyond env)
        ld ta,(rsi); addi rsi,rsi,NBPW
        sd ta,(rdi); addi rdi,rdi,NBPW
         bnez ta,0b
        mv t2,rdi  # &new Elf64_auxv
	mv x18,rdi

0:  // find &strings (beyond auxv)
        ld ta,(rsi); ld tb,NBPW(rsi); addi rsi,rsi,2*NBPW
        sd ta,(rdi); sd tb,NBPW(rdi); addi rdi,rdi,2*NBPW
        bnez ta,0b  # beyond old auxv
    ebreak  // DEBUG
        mv r15,rdi  # beyond new auxv
	mv x16,rsi  # beyond old auxv
        mv r13,rsi  # beginning of strings

        andi ta,r13,unmap_all_pages; beqz ta,0f
          li ta,~0; sw ta,F_MFD(rbp)  # no mfd
	  mv r14,rdi
	  j no_env_pse  # beyond auxv
0:
        jal rdi,0f  // lla rdi,proc_self_exe
proc_self_exe:
        .asciz "/proc/self/exe"
        .balign 4
0:
        li arg3,0  # O_RdONLY
        mv arg2,rdi  // "proc_self_exe"
        call openat_CWD; sw rv,F_MFD(rbp)

        li arg4,-1+ PATH_MAX  # buflen
        mv arg3,sp  # buffer
        mv arg2,rdi  # lla arg2,proc_self_exe
	li arg1,FD_CWD
        syscall __NR_readlinkat; bgez rv,5f
// readlinkat() failed. Set the result equal to the argument.
        mv arg2,rdi  # failure result= "/proc/self/exe"
        li rcx,15  # sizeof "/proc/self/exe"
5:

  // std
        addi rdi,r13,-1  # dst last byte
        sb zero,(rdi)  # terminate
        addi rsi,arg2,-1
        add rsi,rsi,rcx  # src last byte
0:  // slide up (hi end goes first)
        lbu ta,(rsi); addi rsi,rsi,-1; addi rcx,rcx,-1
        sb  ta,(rdi); addi rdi,rdi,-1; bnez rcx,0b
// add new env "   =..."
	li ta,'='; sb ta,(rdi)
        li ta,' '; sb ta,-3(rdi); sb ta,-2(rdi); sb ta,-1(rdi); addi rdi,rdi,-3
        sd rdi,(r14)  # new_env[0]
    ebreak  # DEBUG
        andi rdi,rdi,-NBPW  # align
        sub rcx,r15,sp  # byte count

        addi rdi,rdi,-NBPW   # &last qword of new auxv
        addi rsi,x16,-NBPW   # &last qword of old auxv

        // end of auxv must move by even number of NBPW
        xor ta,rdi,rsi
        andi ta,ta,NBPW
        sub rdi,rdi,ta
        mv r14,rdi  # &last qword of new auxv

        srl rcx,rcx,3
0:
        ld ta,(rsi); addi rsi,rsi,-NBPW; addi rcx,rcx,-1
        sd ta,(rdi); addi rdi,rdi,-NBPW; bnez rcx,0b
        addi sp,rdi,NBPW
  // cld

        addi arg4,t2,NBPW; addi arg4,arg4,NBPW  # &new Elf64_auxv
no_env_pse:
        ld arg1,F_ADRX(rbp)
        ld arg2,F_LENX(rbp)
        andi arg1,arg1,~(is_ptinterp | unmap_all_pages)

        ld arg5,F_ELFA(rbp)  # ELFA | is_ptinterp
        andi ta,arg5,is_ptinterp; or arg4,arg4,ta  # transfer is_ptinterp to &new_ELF64_auxv
        sub arg5,arg5,ta  # and clear from  ELFA
        mv  r13,arg5  # save ELFA
        addi sp,sp,-OVERHEAD
        mv arg3,sp  # &ELf64_Ehdr temporary space
        call upx_main2  # Out: rv= entry

// entry= upx_main2(
// b_info *arg1,       {%rdi}
// total_size arg2,    {%rsi}
// Elf64_Ehdr *arg3,   {%rdx}
// Elf32_Auxv_t *arg4, {%rcx}
// Elf64_Addr elfaddr  {%r8}
// )

// sp/ {OVERHEAD},ADRU,LENU,rdx,%entry,  argc,argv,0,envp,0,auxv,0,strings
        li ta,OVERHEAD
        add sp,sp,ta  # remove Elf64_Ehdr temporary space
        sd rv,3*NBPW(sp)  # entry

        //NYI call *cancel_sigsegv(%rip)

sz_Ehdr= 8*NBPW
e_type= 16
ET_EXEC= 2
sz_Phdr= 7*NBPW
p_memsz= 5*NBPW
// Discard pages of compressed data (includes [ADRX,+LENX) )
        addi arg2,r13,p_memsz+sz_Phdr+sz_Ehdr  #   Phdr[C_TEXT= 1].p_memsz
        //cmpw $ET_EXEC, e_type(%r13); jne 0f
        mv arg1,r13; call brk  // also sets the brk
0:
        mv arg1,r13; call L_munmap  # discard C_TEXT compressed data

// Map 1 page of /proc/self/exe so that the symlink does not disappear.
        lw ta,F_MFD(rbp); bltz ta,no_pse_map
        li arg6,0  # 0 offset
        lw arg5,F_MFD(rbp)
        li arg4,MAP_PRIVATE
        li arg3,PROT_READ
        li arg2,1<<12
        li arg1,0
        call L_mmap

        lw arg1,F_MFD(rbp)
        call L_close

no_pse_map:
        ld arg1,F_ADRU(rbp)  # ADRU: unfolded upx_main2 etc.
        ld arg2,F_LENU(rbp)
        li a7,__NR_munmap
        jr r14  # goto: syscall; pop %rdx; ret

        section SYSCALLS
my_bkpt: .globl my_bkpt
        ebreak  // my_bkpt
        ret

memset: .globl memset  // memset(ptr, c, n)
        beqz arg3,9f
        add arg3,arg3,arg1  // sentinel
        mv ta,arg1  // keep rv == arg1
0:
        sb arg2,0(ta); addi ta,ta,1
        bne arg3,ta,0b
9:
        ret

memcpy: .globl memcpy  // memcpr(dst, src, n)
        beqz arg3,9f
        add arg3,arg3,arg2  // sentinel
        mv ta,arg1  // keep rv == arg1
0:
        lb tb,0(arg2); addi arg2,arg2,1
        sb tb,0(ta); addi ta,ta,1
        bne arg3,arg2,0b
9:
        ret

upxfd_create: .globl upxfd_create // (char *tag, unsigned flags)
// try memfd_create
        syscall __NR_memfd_create; j ok_memfd  //NYI
O_RDWR= 2
O_DIRECTORY= 0200000  // 0x010000
O_TMPFILE= 020000000  // 0x400000
        li arg4,0700  # mode
        li arg3,O_RDWR|O_DIRECTORY|O_TMPFILE
        jal arg2, openat_CWD
        .asciz "/dev/shm"; .balign 4
ok_memfd:
        ret

sysgo:
sys_check:
        ecall; bltz rv,0f
        ret
0:
	ebreak; j 0b
	

Psync: .globl Psync
        li a7,__NR_msync
        j sysgo

open: .globl open
        mv arg4,arg3
        mv arg3,arg2
        mv arg2,arg1
openat_CWD:
        li arg1,FD_CWD
openat: .globl openat
L_openat:
        li a7,__NR_openat;       j 0f
exit: .globl exit
        li a7,__NR_exit;      0: j 0f
brk: .globl brk
        li a7,__NR_brk;       0: j 0f
close: .globl close
L_close:
        li a7,__NR_close;     0: j 0f
ftruncate: .globl ftruncate
        li a7,__NR_ftruncate; 0: j 0f
mprotect: .globl mprotect
        li a7,__NR_mprotect;  0: j 0f
msync: .globl msync
        li a7,__NR_msync;     0: j 0f
Pwrite: .globl Pwrite
write: .globl write
        li a7,__NR_write;     0: j 0f
read: .globl read
        li a7,__NR_read;      0: j sysgo

// vim:set ts=8 sw=8 et:
