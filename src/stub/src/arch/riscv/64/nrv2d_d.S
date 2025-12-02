/* nrv2d_d.S -- RiscV64 decompressor for NRV2D

   This file is part of the UPX executable compressor.

   Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1996-2025 Laszlo Molnar
   Copyright (C) 2000-2025 John F. Reiser
   All Rights Reserved.

   UPX and the UCL library are free software; you can redistribute them
   and/or modify them under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; see the file COPYING.
   If not, write to the Free Software Foundation, Inc.,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   Markus F.X.J. Oberhumer              Laszlo Molnar
   <markus@oberhumer.com>               <ezerotven+github@gmail.com>

   John F. Reiser
   <jreiser@users.sourceforge.net>
*/

#ifndef NO_METHOD_CHECK
        addi pre8,meth,-M_NRV2D_LE32; bnez pre8,not_n2d
#endif
        lui bits,0x80000  // (1<<31): empty; force refill
        li disp,-1  // initial displacement

#undef  DEBUG_NRV
#define DEBUG_NRV 0
#if DEBUG_NRV  //{
#define dst0  x31
#define src0  x30
#define prov0 x29
#define prov  x28
        mv dst0,dst
        mv src0,src
        lui prov0,0x100000>>12
        sub sp,sp,prov0
        mv prov0,sp
        mv prov,sp
#endif  // DEBUG_NRV }

        j top_n2d
lit_n2d:
        addi src,src,1; sb pre8,(dst)
        addi dst,dst,1
top_n2d:
        lbu pre8,(src)  # prefetch: literal, or bottom 8 bits of offset
        jnextb1yp lit_n2d
#define off val
#if DEBUG_NRV  //{
    sub off,src,src0
    sw off,0(prov)
    sw bits,4(prov)
#endif  // DEBUG_NRV }
        li off,1; j getoff_n2d  # the msb

off_n2d:
        addi off,off,-1
        getnextbp(foo)
getoff_n2d:
        getnextbp(off)
        jnextb0 off_n2d

        addiw off,off,-3; bltz off,len_n2d  # use previous offset
        slli  off,off,8; addi src,src,1  # account for previous fetch
// XXX 2GB; addw needs sign extend (32-->64) at EOF
        addw  off,off,pre8; lbu pre8,0(src)  # prefecth
        xori disp,off,~0  # no xoriw, so need previous addw
#undef off
        beqz disp,l_n2d_EOF

offprev_n2d:
        getnextb(len); j pointC

len_n2d:
        getnextb(len); jne gotlen_n2d
        inc len  // len= 1
lenmore_n2d:
        getnextb(len)
        jnextb0n lenmore_n2d
        addl $2,len
gotlen_n2d:
        cmpq $-0x500,dispq
        adcl $1,len  // len += 1+ (disp < -0x500);
        call copy
bot_n2d:  // In: 0==len
        jmp top_n2d

#ifndef NO_METHOD_CHECK
not_n2d:
        push %rdi; pop %rsi  # src = arg1
#endif
        // fall into daisy chain
/*
vi:ts=8:et:nowrap
*/

