/*  riscv64-linux.elf-entry.S -- Linux program entry point & decompressor (Elf binary)
*
*  This file is part of the UPX executable compressor.
*
*  Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
*  Copyright (C) 1996-2025 Laszlo Molnar
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

#include "arch/riscv/64/macros.S"
#include "arch/riscv/64/regs.h"
NBPW= 8

/* These from /usr/include/unistd_64.h */
__NR_close=     57
__NR_exit=      93
__NR_ftruncate= 64
__NR_memfd_create= 279
__NR_mmap=     222
__NR_mprotect= 226
__NR_msync=    227
__NR_openat=    56
__NR_write=     64

sz_Ehdr= 64
e_phnum= 56
sz_Phdr= 56

sz_l_info= 12
  l_lsize= 8

sz_p_info= 12

sz_b_info= 12
  sz_unc= 0
  sz_cpr= 4
  b_method= 8

AT_PAGESZ= 6

PROT_READ=  1
PROT_WRITE= 2
PROT_EXEC=  4

MAP_SHARED=  1
MAP_PRIVATE= 2
MAP_FIXED=     0x10
MAP_ANONYMOUS= 0x20

MFD_EXEC= 0x0010

SYS_mmap= 9  // 64-bit mode only!

FD_stderr= 2

M_NRV2B_LE32=2  // ../conf.h
M_NRV2D_LE32=5
M_NRV2E_LE32=8


// https://www.uclibc.org/docs/psABI-x86_64.pdf
  section ELFMAINX
sz_pack2= .-4
_start: .globl _start
////    nop; int3  # uncomment for debugging

        ld s0,0(sp)  // argc
        addi s1,sp,NBPW  // argv
        //NYI lea cancel_dummy(%rip),%r15

  section ELFMAINX2

// same as in riscv64-linux.elf-fold.S
F_FRAME= 8*NBPW
F_EOF=  7*NBPW
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

// find auxv
        slli t0,s0,3  // NBPW * argc
        add t0,t0,a1  // end argv
0: // find end of env
        addi t0,t0,NBPW  // &env[k]
        ld t1,(t0); bnez t1,0b

// find AT_PAGESZ in auxv
        addi t0,t0,NBPW  // &auxv
        li a7,AT_PAGESZ  // desired key
0:
        ld t1,(t0); ld t2,NBPW(t0); addi t0,t0,2*NBPW
        beq t1,a7,1f  // found it
        bne t1,zero,0b  // keep searching
        li t2,0x1000  // default PAGE_SIZE
1:
        sub a7,zero,t2  // PAGE_MASK
2:
// Create anonymous temporary file on mfd; like upxfd_create
        jal arg1,0f
str_upx:
        .asciz "upx"
0:
//        lla arg1,str_upx
        li arg2,MFD_EXEC  // flags
        syscall __NR_memfd_create
        bne a0,zero,ok_memfd  // success
no_memfd:  // so try /dev/shm

O_RDWR= 2
O_DIRECTORY= 0200000  // 0x010000
O_TMPFILE= 020000000  // 0x400000
#        lla arg1,str_devmem
        jal arg1,0f
str_devmem:
        .asciz "/dev/mem"
        .balign 4
0:
        li arg2,0700  // mode
        li arg3,O_RDWR | O_TMPFILE | O_DIRECTORY
        syscall __NR_openat
ok_memfd:
#define mfd s2
        mv mfd,rv

        lla t0,sz_pack2
#define elfa s3
        lw t1,(t0); sub elfa,t0,t1
#define binf s4
        lla binf,4+o_binfo
#define lenu s5
        lw lenu,sz_unc(binf)
#define szp2 s6
#define lenx s7
        sub lenx,szp2,binf
#define adrx s8
        add adrx,elfa,binf

#define old_sp s9
        mv old_sp,sp
// alloca()
        sub sp,sp,lenu; andi sp,sp,-2*NBPW

// Decompress the rest of this loader, and jump to it.

#define dst  a2
#define src  a0
#define lsrc a1
        mv dst,sp
        lw lsrc,sz_cpr(binf)
        lbu t0,b_method(binf); li t1,M_NRV2B_LE32|(0<<8); beq t0,t1,0f; ebreak
0:
        add t0,lsrc,src; sw t0,F_EOF(old_sp)
//%rsp:
//  MATCH_10  old_sp
//  MATCH_11  &input_eof

//%rbp  === old_sp:  array of F_FRAME

#define src  a0
#define bits a1
#define dst  a2
#define off  a3
#define len  a4
#define disp a5
#define retbit t0
#define bytpre t1

/* jump on next bit {0,1} with prediction {y==>likely, n==>unlikely} */
/* Prediction omitted for now. */

#define jnextb0np jnextb0yp
#define jnextb0yp GETBITp; beq retbit,zero,
#define jnextb1np jnextb1yp
#define jnextb1yp GETBITp; bne retbit,zero,
#define GETBITp \
        call getbit

/* Same, but without prefetch (not useful for length of match.) */
#define jnextb0n jnextb0y
#define jnextb0y GETBIT; beq retbit,zero,
#define jnextb1n jnextb1y
#define jnextb1y GETBIT; bne retbit,zero,
#define GETBIT \
        call getbit

/* rotate next bit into bottom bit of reg */
#define getnextbp(reg) GETBITp; slli reg,reg,1;  or reg,reg,retbit
#define getnextb(reg)  getnextbp(reg)

// We already checked the method and no filter.
#define NO_METHOD_CHECK 1
#include "arch/riscv/64/nrv2b_d.S"

getbit:
        srli retbit,bits,63  # hi bit of 64
        slli bits,bits,1; beq bits,zero,refill
        ret
/* On refill: prefetch next byte, for latency reduction on literals and offsets. */
refill:
        lw bits,(src); addi src,src,4
        srli retbit,bits,31  # hi bit of 4 bytes fetched
        slli bits,bits,1; lbu bytpre,(src)  # prefetch
        ori  bits,bits,1  # the flag bit
        slli bits,bits,32  # hi 32 bits in 64-bit register
        ret

n2b_EOFbad:
        ebreak
eof_n2b:
        lw t0,F_EOF(old_sp)
        bne t0,src,n2b_EOFbad

// Write de-compressed 'fold' to file
        lw t0,F_PMASK(old_sp); sw t0,D_PMASK(sp)  // propagate PAGE_MASK
        lwu arg3,F_LENU(old_sp)
        mv arg2,sp
        mv arg1,mfd
        mv s2,arg3  // LENU
0:  // /dev/shm might be restricted to 8KiB at a time!
        syscall __NR_write
        add arg2,arg2,rv  // ptr += count
        sub  arg3,arg3,rv  // decrement count
        bnez arg3,0b  // not finished
// de-alloca()
        mv sp,old_sp

// Map unfolded code the SELinux way
        li arg6,0  // offset
        mv arg5,mfd
        li arg4,MAP_SHARED
        li arg3,PROT_READ|PROT_EXEC  // FIXME: add PROT_WRITE for DEBUG only
        mv arg2,s2  // LENU
        li arg1,0  // (%arg1)dst = 0;  // kernel chooses addr
        syscall __NR_mmap
        sw rv,F_ADRU(old_sp)

        mv arg1,mfd
        syscall __NR_close

// Use the copy.
        ld a0,F_ADRU(sp)  //
        addi a0,a0,D_FOLD  // beyond .data
        jr a0  // goto unfolded stub

        // IDENTSTR goes here

  section ELFMAINZ
        .balign 4
o_binfo:
        .long O_BINFO  // offset of b_info for .text | is_ptinerp | unmap_all_pages
FOLD:
        // { b_info={sz_unc, sz_cpr, {4 char}}, folded_loader...}

/*__XTHEENDX__*/

/* vim:set ts=8 sw=8 et: */
