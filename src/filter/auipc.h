/* auipc.h -- auipc filter for RiscV

   This file is part of the UPX executable compressor.

   Copyright (C) 2026 John F. Reiser
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

   John F. Reiser
   <jreiser@users.sourceforge.net>
 */

// Do not change columns or whitespace!
// I write code with adjacent lines that should match spacing.
// filter/auipc.h has been added to CLANG_FORMAT_EXCLUDE_FILES in Makefile.

// Use 'int' instead of 'unsigned' because gcc for RiscV does not realize
// that everything fits in 32 bits, so often uses "slli reg,32; srli reg,32"
// to force 32-bit unsigned; but this is not needed.

/*************************************************************************
// filter / scan
**************************************************************************/
#if 0  //{ wide ASCII-art documentation
// The original layout is:
 31                                              12 11          7 6          0
+--------------------------------------------------+-------------+------------+
|                      imm[31:12]                  |   r_aui     |   AUIPC    |
+-------------+-------------+-------------+--------+-------------+------------+
|        imm[11:0]          |    r_aui    |  func3 |     rd      |   opcode   |
+-------------+-------------+-------------+--------+-------------+------------+
 31         25 24         20 19         15 14    12 11          7 6          0

// The filtered layout is:
 31                24 23                16 15    12 11       8  7 6          0
+--------------------+--------------------+-------------------+--+------------+
|    addr_mid_lo     |    addr_mid_hi     |     addr_MSB      |a0|   AUIPC    |
+-----------+--------+------------+-------+--------+----------+--+------------+
|   r_aui   |  func3 |     rd     |    opcode      |    r_aui    | a_lsB[7:1] |
+-----------+--------+------------+----------------+-------------+------------+
 31       27 26    24 23        19 18            12 11          7 6          0
#endif  //}

#ifndef CONDf //{ once-only during multiple #include of this file
// Input to filtering/scanning
#define AUIPC 0x17
#define opf(w) (0x7f& (w))
#define     rd(i_type) (037& ((i_type) >> 7))
#define func3f(i_type) (  7& ((i_type) >>12))
#define   rs1f(i_type) (037& ((i_type) >>15))

#define COND(word1) (AUIPC==opf(word1))

#define CONDf(word2, r_aui) ( r_aui==rs1f(word2) && ( \
         0x03==opf(word2) /*FETCH*/ \
     || (0x67==opf(word2) && 0==func3f(word2)) /*JALR*/ \
     || (0x13==opf(word2) && 0==func3f(word2)) /*ADDI*/ \
    ) )
// NYI: STOREs are ugly because immediate field is not contiguous
//    ||  0x23==opf(word2) /*STORE*/

#endif  //}

static int F(Filter *f) {
#ifdef U
    // If both F and U defined then action is Filter; else Scan.
    // filter
    byte *b = f->buf;
#else
    // scan only
    const byte *b = f->buf;
#endif
    const int size = f->buf_len;

    int ic;
    int calls = 0, noncalls = 0;
    int lastcall = 0;

    int ilen;
    for (ic = 0; ic < size - 8; ic += ilen) {
        int word1 = get_le32(ic + b);
        ilen = 2;
        if (3 == (3& (word1 >>0))) {
            ilen += 2;
            if (3 == (3& (word1 >>2))) {
                ilen += 2;
                // NYI: 8 bytes or longer
            }
        }
        if (!COND(word1)) {
            continue;
        }
        int r_aui = rd(word1);
        int word2 = get_le32(4+ic+b);
        if (!CONDf(word2, r_aui)) {
            ++noncalls;
            continue;
        }
        ilen = 8; // next is after word2
        // Filtering requires displacement < 1GB
        // becase top 2 bits of addr are used as markers.
#ifdef U  //{ filtering
        int addr = ((~0xfff& word1) + (word2 >>20));  // sign extend imm
#endif  //}
        if (((word1 <<1) ^ word1) < 0) {
            // Incoming top 2 bits are unequal, so the displacment is >= 1GB.
            ++noncalls;
        }
        else {
            // Incoming top 2 bits are the same, so the displacement is < 1GB.
#ifdef U  //{ filtering
            addr += ic;  // AUIPC result value
#endif  //}
            lastcall = ic;
            ++calls;
        }
#ifdef U  //{ filtering
        *(0+ic+b) = ((1& addr) <<7) | AUIPC;  // lo bit of addr adjacent to AUIPC
                                              //
        // The filtered output has the true hoisted address.
        //addr += ((1u <<11)& addr) <<1;

        addr ^= (1u<<31);  // change parity of top 2 bits
        set_be32(1+ic+b, addr);  // Note BIG_ENDIAN store
        set_le32(4+ic+b, (word2 <<12) | (r_aui <<7) | (0x7f& (addr >>1)));
        if (0) { // DEBUG
            char line[100];
            int len = snprintf(line, sizeof(line), "%#6x  %#8.8x %#8.8x  %#8.8x %#8.8x\n",
                ic, word1, word2, get_le32(0+ic+b), get_le32(4+ic+b));
            if (len != write(7, line, len)) {
                exit(7);
            }
        }
#endif  //}
    }

    f->calls = calls;
    f->noncalls = noncalls;
    f->lastcall = lastcall;

#if 0 || defined(TESTING)
    printf("\ncalls=%d  noncalls=%d  text_size=%#x\n",calls,noncalls,size);
#endif
    return 0;
}

#ifdef U  //{
// Input to un-filtering: then the second instruction has been rotated left
// by 12 bits, and the Immediate field replaced by r_aui and a_lsB[7:1] .
#define opu(w) opf((w) >>12)
#define func3u(i_type) (  7& ((i_type) >>24))
#define   rs1u(i_type) (037& ((i_type) >>27))

#define CONDu(word2, r_aui) ( r_aui==rs1u(word2) && ( \
         0x03==opu(word2) /*FETCH*/ \
     || (0x67==opu(word2) && 0==func3u(word2)) /*JALR*/ \
     || (0x13==opu(word2) && 0==func3u(word2)) /*ADDI*/ \
    ) )

static int U(Filter *f) {
    byte *b = f->buf;
    const int size = f->buf_len;

    int ic;
    int calls = 0, noncalls = 0;
    int lastcall = 0;

    int ilen;
    for (ic = 0; ic < size - 8; ic += ilen) {
        int word1 = get_le32(  ic+b);
        ilen = 2;
        if (3 == (3& (word1 >>0))) {
            ilen += 2;
            if (3 == (3& (word1 >>2))) {
                ilen += 2;
                // NYI: 8 bytes or longer
            }
        }
        int word2 = get_le32(4+ic+b);
        int r_aui = 037& (word2 >> 7);
        if (!(AUIPC==opf(word1))) {
            continue;
        }
        if (!CONDu(word2, r_aui)) {
            ++noncalls;
            continue;
        }
        ilen = 8;  // next is after word2

        int addr = get_be32(1+ic+b);  // Note BIG_ENDIAN fetch
        addr = (~0xff & addr) | ((0x7f& addr) <<1) | (1& (word1 >>7));
        if (((addr<<1) ^ addr) < 0) {
            // Incoming top 2 bits differ (original top 2 bits are equal),
            // so the displacment is < 1GB, and filtering hoisted the AUIPC
            addr -= ic;  // un-hoist the effect of AUIPC
            lastcall = ic;
            ++calls;
        }
        else {
            // Incoming top 2 bits are equal (original top 2 bits differ)
            // so the displacement is >= 1GB, and filtering did not change addr.
            ++noncalls;
        }
        addr += ((1u <<11)& addr) <<1;  // 12-bit imm is sign-extended
        addr ^= (1u<<31);  // change parity of top 2 bits
        set_le32(0+ic+b, (~0xfff& addr) | (r_aui <<7) | AUIPC);
        set_le32(4+ic+b,    (addr <<20) | ((unsigned)word2 >>12));
        if (0) { // DEBUG
            char line[100];
            int len = snprintf(line, sizeof(line), "%#6x  %#8.8x %#8.8x  %#8.8x %#8.8x\n",
                ic, get_le32(0+ic+b), get_le32(4+ic+b), word1, word2);
            if (len != write(8, line, len)) {
                exit(8);
            }
        }
    }

    f->calls = calls;
    f->noncalls = noncalls;
    f->lastcall = lastcall;

#if 0 || defined(TESTING)
    printf("\ncalls=%d  noncalls=%d  text_size=%#x\n",calls,noncalls,size);
#endif
    return 0;
}
#endif  //}

/* vim:set ts=4 sw=4 et: */
