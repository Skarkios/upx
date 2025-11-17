/*
;  riscv64-expand.S -- decompressors for riscv64
;
;  This file is part of the UPX executable compressor.
;
;  Copyright (C) 1996-2021 Markus Franz Xaver Johannes Oberhumer
;  Copyright (C) 1996-2021 Laszlo Molnar
;  Copyright (C) 2000-2021 John F. Reiser
;  All Rights Reserved.
;
;  UPX and the UCL library are free software; you can redistribute them
;  and/or modify them under the terms of the GNU General Public License as
;  published by the Free Software Foundation; either version 2 of
;  the License, or (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program; see the file COPYING.
;  If not, write to the Free Software Foundation, Inc.,
;  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
;
;  Markus F.X.J. Oberhumer              Laszlo Molnar
;  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
;
;  John F. Reiser
;  <jreiser@users.sourceforge.net>
;
*/

NBPW = 8
#include "arch/riscv/64/macros.S"
.macro call subr; jal \subr; .endm

  section EXP_HEAD

sz_unc= 0
sz_cpr= 4
b_method= 8
b_ftid=   9
b_cto8=  10
b_extra= 11
sz_binfo= 12

f_expand: .globl f_expand // f_expand(b_info *, dst, &dstlen)
// Supervisor for de-compression, un-filter, and sync_cache
// Input to supervisor:
#define fx_src a0
#define fx_dst a1
#define fx_dstlen a2
    PUSH4 fx_src,fx_dst,fx_dstlen,ra  // MATCH_95 params to unfilter and sync_cache

// Input to de-compressor:
#define xsrc    a0
#define xsrclen a1
#define xdst    a2
#define xdstlen a3
#define meth    a4
    lbu meth,b_method(fx_src)
    mv xdstlen,fx_dstlen  // arg4
    mv xdst,fx_dst  // arg3
    lw xsrclen,sz_cpr(xsrc)  // arg2
    addi xsrc,fx_src,sz_binfo // arg1
    call decompress
    mv a3,a0  // save retval

    POP4 fx_src,fx_dst,fx_dstlen,ra  // MATCH_95  fx_src,fx_dst,fx_dstlen,ra
    lw fx_dst,(fx_dst)  // actual length used by decompressor
    PUSH3 fx_src,fx_dst,a2   // MATCH_96  params for sync_cache
    lbu a3,b_ftid(sp)
    lbu a2,b_cto8(sp)
    beqz a3,no_unf
//NYI #include "arch/arm64/v8/bxx.S"  // unfilter code; args in registers, fall-through return
no_unf:

    POP2 a0,a1   // MATCH_96  dst, len
    add a1,a1,a0  // lo, hi
    //NYI sync_cache  // in macros.S
    POP1 a0   // MATCH_96  retval from decompress
    ret
#undef fx_src
#undef fx_dst
#undef fx_dstlen
#undef xsrc
#undef xsrclen
#undef xdst
#undef xdstlen

decompress:  // (src *, cpr_len, dst *, &dstlen);
//  sections NRV2B, etc, inserted here by addLoader() from ::buildLinuxLoader()

  section EXP_TAIL
// Fall through: daisy chain had no matching method
        li a0,-1
        mv a1,meth
        ebreak  // EXP_TAIL daisy chain fail

#define src  a0
#define bits a1
#define dst  a2
#define off  a3
#define len  a4
#define disp a5
#define retbit t0
#define bytpre t1


  .globl eof

// sync_cache is done in tail of f_expand, after possible unfilter
// NYI: eof_n2b, eof_n2d, eof_n2e should be unified.
eof_n2b: // .globl eof_n2b .type eof_n2b,%function
eof:  // MATCH_90  end of a compressed extent; need sync_cache after unfilter
        ld a2,0*NBPW(sp)  // &input_eof
        sub a0,src,a3  // src -= eof;  // return 0: good; else: bad
        ld a1,1*NBPW(sp)  // original dst
        sub dst,dst,a1  // dst -= original dst; actual length of output
        ld a1,2*NBPW(sp)  // &dstlen
        sw dst,(a1)  // actual length used at dst  XXX: 4GB
        ld ra,3*NBPW(sp)
        addi sp,sp,4*NBPW
        ret


// WINDOWS_BACK compatibility seems to be broken
// if POP3 replaces POP2+POP1 (MATCH_92, MATCH_91)
#define srclim  a7
eof_n2d: // .globl eof_n2d
eof_n2e: // .globl eof_n2e
        POP2 a3,a4   // MATCH_92  r3= orig_dst; r4= plen_dst
        SUB2 src,srclim   // 0 if actual src length equals expected length
        SUB2 dst,a3   // actual dst length
        sw dst,(a4)
        POP1 ra  // MATCH_91
        ret

eof_lzma: .globl eof_lzma
        POP4 x2,x3, fp,ra   // MATCH_94  x2= orig_dst; x3= plen_dst
        ret

upx_mmap_and_fd: .globl upx_mmap_and_fd
    // UMF_LINUX goes here

#define M_NRV2B_LE32    2
#define M_NRV2B_8    3
#define M_NRV2D_LE32    5
#define M_NRV2D_8    6
#define M_NRV2E_LE32    8
#define M_NRV2E_8    9
#define M_CL1B_LE32     11
#define M_LZMA          14

#define NO_METHOD_CHECK 1  /* subsumed here by daisy chain */

getbit:
        srliw retbit,bits,31  # hi bit of 32
        addw bits,bits,bits; beqz bits,refill
        ret
/* On refill: prefetch next byte, for latency reduction on literals and offsets. */
refill:
        lw bits,(src); addi src,src,4
        srliw retbit,bits,31  # hi bit of 4 bytes fetched
        slli bits,bits,1; lbu bytpre,(src)  # prefetch
        addiw bits,bits,1  # the flag bit
        ret

#define rax a0  /* x10 */
#define rdx t1  /* x6 */
copy:  // In: len, dst, dispq;  Out: 0==len, dst, dispq;  trashes %rax, %rdx
   ebreak
        add rax,dst,disp; li t0,5; sgtu t0,t0,len  // <=3 is forced
        lbu rdx,0(rax); bnez t0,copy1  // <=5 for better branch predict
        li t0,-4; sgtu t0,disp,t0; bnez t0,copy1  // 4-byte chunks would overlap
        addi len,len,-4  // adjust for termination cases
        add t0,len,dst
copy4:
        lwu rdx,0(rax); addi rax,rax,4
        sw  rdx,0(dst); addi dst,dst,4; bgeu dst,len,copy4
        addi len,len,4; lbu rdx,0(rax); beqz len,copy0
copy1:
        addi rax,rax,1; lbu rdx,0(dst); addi len,len,-1
            lbu rdx,0(rax)
                addi dst,dst,1;  bnez len,copy1
copy0:
        ret

/* jump on next bit {0,1} with prediction {y==>likely, n==>unlikely} */
/* Prediction omitted for now. */

#define jnextb0np jnextb0yp
#define jnextb0yp GETBITp; beqz retbit,
#define jnextb1np jnextb1yp
#define jnextb1yp GETBITp; bnez retbit,
#define GETBITp \
        call getbit

/* Same, but without prefetch (not useful for length of match.) */
#define jnextb0n jnextb0y
#define jnextb0y GETBIT; beqz retbit,
#define jnextb1n jnextb1y
#define jnextb1y GETBIT; bnea retbit,
#define GETBIT \
        call getbit

/* rotate next bit into bottom bit of reg */
#define getnextbp(reg) GETBITp; slli reg,reg,1;  or reg,reg,retbit
#define getnextb(reg)  getnextbp(reg)

  section NRV2E
    li t0,M_NRV2E_LE32; bne meth,t0,not_nrv2e
//NYI #include "arch/arm64/v8/nrv2e_d.S"
not_nrv2e:

  section NRV2D
    li t0,M_NRV2D_LE32; bne meth,t0,not_nrv2d
//NYI #include "arch/arm64/v8/nrv2d_d.S"
not_nrv2d:

  section NRV2B
    li t0,M_NRV2B_LE32; bne meth,t0,not_nrv2b
#include "arch/riscv/64/nrv2b_d.S"
not_nrv2b:

  section LZMA_DAISY
    li t0,M_LZMA; bne meth,t0,not_lzma
//NYI #include "arch/arm64/v8/lzma_d.S"
not_lzma:
