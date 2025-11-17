/* riscv64 nrv2b_d.S -- RISCV64 decompressor for NRV2B

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
        cmpb $ M_NRV2B_LE32,methb; jne not_n2b
#endif
        lui bits,0x80000  // (1<<31): empty; force refill
        li len,0
        li disp,-1  // initial displacement
        j top_n2b

#undef EOF
#define EOF eof_n2b

lit_n2b:
        addi src,src,1; sb bytpre,(dst)
        addi dst,dst,1
top_n2b:
        lbu bytpre,(src)  # prefetch: literal, or bottom 8 bits of offset
        jnextb1yp lit_n2b
        li off,1
offmore_n2b:
        getnextbp(off)
        jnextb0np offmore_n2b

        addiw off,off,-3; bltz off,len_n2b  # use previous offset
        slliw off,off,8
        addw  off,off,bytpre; addi src,src,1
        xori disp,off,~0; beqz disp,EOF
len_n2b:
        li off,1
        getnextb(len); getnextb(len)  # two bits; cc set on result
        bnez len,gotlen_n2b  # raw 1,2,3 ==> 2,3,4
        mv len,off  # len= 1, the msb
        addiw off,off,3-1  # raw 2.. ==> 5..
lenmore_n2b:
        getnextb(len)
        jnextb0n lenmore_n2b
gotlen_n2b:
        li t0,-0xd00
        sltu retbit,t0,disp
        add len,len,off; add len,len,retbit  # len += off + (disp < -0xd00)
        call copy
bot_n2b:  # In: 0==len
        j top_n2b

#ifndef NO_METHOD_CHECK  //{
not_n2b:
        push %rdi; pop %rsi  # src = arg1
#endif  //}

        # fall into daisy chain
/*
vi:ts=8:et:nowrap
*/

