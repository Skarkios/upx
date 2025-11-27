// Must be first in this file to make "jal x5,xin_..." work.
getbit:
        srliw rbit,bits,31  # hi bit of 32
        addw bits,bits,bits; beqz bits,refill
        ret
/* On refill: prefetch next byte, for latency reduction on literals and offsets. */
refill:
// Unaligned: profile RVA22U64 with required extension Ziccism allows trap (slow)
#if 0  //{
        lw bits,(src)
#else  //}{
     // lbu pre8,0(src)  # already done
        lbu bits,1(src);    slli bits,bits,1*8
        lbu rbit,2(src);    or   bits,bits,pre8
        lbu pre8,3(src);    slli rbit,rbit,2*8
                            or   bits,bits,rbit
                            slli pre8,pre8,3*8
                            or   bits,bits,pre8
#endif  //}
	addi src,src,4  

        srliw rbit,bits,31  # hi bit of 4 bytes fetched
        slli bits,bits,1; lbu pre8,(src)  # prefetch
        addiw bits,bits,1  # the flag bit
        ret

copy:  // In: len, dst, disp; typically short: len <= 6
#define tmp ta
#define len val
        add tmp,dst,disp  # src
        add len,dst,len  # limit
        lbu pre8,0(tmp)  # prime the pump
0:
        sb  pre8,0(dst); addi dst,dst,1
        lbu pre8,1(tmp); addi tmp,tmp,1; bne dst,len,0b
        ret
#undef len
#undef tmp

