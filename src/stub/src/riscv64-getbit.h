// registers during NRV/UCL de-compress code
#define dst  x15  /* a5  rdi */
#define src  x14  /* a4  rsi */
#define disp x13  /* a3  rbp */
#define ta   x12  /* a2  rsp */
#define bits x11  /* a1  rbx */
#define rbit x10  /* a0  rax   rv */
#define pre8 x9   /* s1  rdx */
#define val  x8   /* s0  rcx   fp */

/* jump on next bit {0,1} with prediction {y==>likely, n==>unlikely} */
/* Prediction omitted for now. */

#define jnextb0np jnextb0yp
#define jnextb0yp GETBITp; beqz rbit,
#define jnextb1np jnextb1yp
#define jnextb1yp GETBITp; bnez rbit,
#define GETBITp \
        jalr x5

/* Same, but without prefetch (not useful for length of match.) */
#define jnextb0n jnextb0y
#define jnextb0y GETBIT; beqz rbit,
#define jnextb1n jnextb1y
#define jnextb1y GETBIT; bnez rbit,
#define GETBIT \
        jalr x5

/* rotate next bit into bottom bit of reg */
#define getnextbp(reg) GETBITp; slli reg,reg,1;  or reg,reg,rbit
#define getnextb(reg)  getnextbp(reg)

