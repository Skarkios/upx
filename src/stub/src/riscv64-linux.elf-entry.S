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

FD_CWD= -100

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

// same as in riscv64-linux.elf-fold.S
F_FRAME= 8*NBPW
F_EOF=  7*NBPW
F_ENTR= 6*NBPW; F_PMASK= F_ENTR
F_RDX=  5*NBPW
F_LENU= 4*NBPW
F_ADRU= 3*NBPW
F_ELFA= 2*NBPW
F_LENX= 1*NBPW  # 4 bytes only
F_MFD=  1*NBPW + 4
F_ADRX= 0*NBPW

D_FOLD=  2*NBPW  // .data space at start of unfold
D_PMASK= 0*NBPW
D_XSIGSEGV= 1*NBPW

// https://www.uclibc.org/docs/psABI-x86_64.pdf
  section ELFMAINX
#define elfa s3
sz_pack2= .-4
_start: .globl _start
        jal t0,0f; 0: addi t0,t0,-8  // &sz_pack2

////    nop; int3  # uncomment for debugging
#define szp2 s6
        lwu szp2,0(t0)  // sz_pack2
        sub elfa,t0,szp2

        ld s0,0(sp)  // argc
        addi s1,sp,NBPW  // &argv

        addi sp,sp,-F_FRAME
        sd elfa,F_ELFA(sp)
        sd szp2,F_EOF(sp)

        //NYI lea cancel_dummy(%rip),%r15

  section ELFMAINX2

// find auxv
        slli t0,s0,3  // NBPW * argc
        add t0,t0,s1  // end argv
0: // find end of env
        addi t0,t0,NBPW  // &env[k]
        ld t1,(t0); bnez t1,0b

// find AT_PAGESZ in auxv
        addi t0,t0,NBPW  // &auxv
        li a7,AT_PAGESZ  // desired key
0:
        ld t1,(t0); ld t2,NBPW(t0); addi t0,t0,2*NBPW
        beq t1,a7,9f  // found it
        bnez t1,0b  // keep searching
        li t2,0x1000  // default PAGE_SIZE
9:
        neg a7,t2  // PAGE_MASK
        sd a7,F_PMASK(sp)
// Create anonymous temporary file on mfd; like upxfd_create
        jal arg1,0f
        .asciz "upx"  // 4==size; no .balign needed
0:
        li arg2,MFD_EXEC  // flags
        syscall __NR_memfd_create
        bgez a0,9f  // success
            // failure, so try /dev/mem
O_RDWR= 2
O_DIRECTORY= 0200000  // 0x010000
O_TMPFILE= 020000000  // 0x400000
        li arg4,0700  // mode
        li arg3,O_RDWR | O_TMPFILE | O_DIRECTORY
        jal arg2,0f
        .ascii "/dev/mem"; .int 0  // .balign causes problems
0:
        li arg1,FD_CWD
        syscall __NR_openat
9:
        sw rv,F_MFD(sp)

#define binf s4
        jal mainz
#define lenu s5
        lw lenu,4+sz_unc(binf)
        sd lenu,F_LENU(sp)
#define lenx s7
        sub lenx,binf,elfa
        sw lenx,F_LENX(sp)
#define adrx s8
        lwu t0,0(binf); andi t0,t0,~3
        add adrx,elfa,t0
        sd adrx,F_ADRX(sp)

#define old_sp s9
        mv old_sp,sp
// alloca()
        sub sp,sp,lenu; andi sp,sp,-2*NBPW

// Decompress the rest of this loader, and jump to it.

#define dst  a2
#define src  a0
#define lsrc a4  /* len */
        mv dst,sp
        lw lsrc,4+sz_cpr(binf)
        lbu t0,4+b_method(binf); li t1,M_NRV2B_LE32|(0<<8)
        beq t0,t1,0f; ebreak; 0:  # elf_entry wrong method
        addi src,binf,4 + sz_b_info
        add lsrc,lsrc,src; sd lsrc,F_EOF(old_sp)
//s9  === old_sp:  array of F_FRAME

#define src  a0
#define bits a1
#define dst  a2
#define off  a3
#define len  a4
#define disp a5
#define rbit t0
#define pre8 t1

/* jump on next bit {0,1} with prediction {y==>likely, n==>unlikely} */
/* Prediction omitted for now. */

#define jnextb0np jnextb0yp
#define jnextb0yp GETBITp; beqz rbit,
#define jnextb1np jnextb1yp
#define jnextb1yp GETBITp; bnez rbit,
#define GETBITp \
        call getbit

/* Same, but without prefetch (not useful for length of match.) */
#define jnextb0n jnextb0y
#define jnextb0y GETBIT; beqz rbit,
#define jnextb1n jnextb1y
#define jnextb1y GETBIT; bnez rbit,
#define GETBIT \
        call getbit

/* rotate next bit into bottom bit of reg */
#define getnextbp(reg) GETBITp; slli reg,reg,1;  add reg,reg,rbit
#define getnextb(reg)  getnextbp(reg)

// We already checked the method and no filter.
#define NO_METHOD_CHECK 1
#include "arch/riscv/64/nrv2b_d.S"

getbit:
        srliw rbit,bits,31  # hi bit of 32
        addw bits,bits,bits  # slliw is 4 bytes
        beqz bits,refill  # addw 32-bits zero <==> all bits zero
        ret
refill:
// Unaligned: profile RVA22U64 with required extension Ziccism allows trap (slow)
     // lbu pre8,0(src)  # already done
        lbu bits,  1(src); slli bits,bits,1*8
        lbu t0,    2(src); or   bits,bits,pre8
        lbu pre8,3(src);     slli t0,t0,2*8
        or  bits,bits,t0;   slli pre8,pre8,3*8
        or  bits,bits,pre8
        lbu pre8,4(src); addi src,src,4  # prefetch

        srliw rbit,bits,31  # hi bit of 4 bytes fetched
        slli  bits,bits,1
        addi  bits,bits,1  # the flag bit
        ret

copy:  // In: len, dst, disp; typically short: len <= 6
#define tmp off
        add tmp,dst,disp  # src
        add len,dst,len  # limit
        lbu pre8,0(tmp)  # prime the pump
0:
        sb  pre8,0(dst); addi dst,dst,1
        lbu pre8,1(tmp); addi tmp,tmp,1; bne dst,len,0b
        ret
#undef tmp

n2b_EOFbad:
        ebreak  # elf-entry n2b_EOFbad
eof_n2b:
        ld t0,F_EOF(old_sp)
        bne t0,src,n2b_EOFbad

// propagate F_PMASK(old_sp) into c.lui at D_PMASK(sp)
        lhu t0,F_PMASK(old_sp)
        lhu t1,D_PMASK(sp)  # old c.lui
        srli t0,t0,12-2  # position PMASK to nzimm[16:12]
        xor t1,t1,t0  # bits which differ
        andi t0,t0,037<<2  # restrict to nzimm[16:12]
        xor t0,t0,t1  # change them
        sh t0,D_PMASK(sp)  # new c.lui

// Write de-compressed 'fold' to file
        lwu arg3,F_LENU(old_sp)
        mv arg2,sp
        lwu arg1,F_MFD(old_sp)
L360:  // /dev/shm might be restricted to 8KiB at a time!
        syscall __NR_write
        add arg2,arg2,rv  // ptr += count
        sub  arg3,arg3,rv  // decrement count
        bnez arg3,L360  // not finished
// de-alloca()
        mv sp,old_sp

// Map unfolded code the SELinux way
        li arg6,0  // offset
        lwu arg5,F_MFD(sp)
        li arg4,MAP_PRIVATE
        li arg3,PROT_EXEC|PROT_READ  // FIXME: add PROT_WRITE for DEBUG only
        lwu arg2,F_LENU(sp)
        li arg1,0  // (%arg1)dst = 0;  // kernel chooses addr
        syscall __NR_mmap; bgez rv,0f; ebreak; 0:
        sd rv,F_ADRU(sp)

        lwu arg1,F_MFD(sp)
        syscall __NR_close

// Use the copy.
        ld a0,F_ADRU(sp)  //
        addi a0,a0,D_FOLD  // beyond .data
        jr a0  // goto unfolded stub

        // IDENTSTR goes here

  section ELFMAINZ
        .balign 4
mainz:
        jalr binf,ra
        .long O_BINFO  // offset of b_info for .text | is_ptinerp | unmap_all_pages
FOLD:
        // { b_info={sz_unc, sz_cpr, {4 char}}, folded_loader...}

/*__XTHEENDX__*/

/* vim:set ts=8 sw=8 et: */
