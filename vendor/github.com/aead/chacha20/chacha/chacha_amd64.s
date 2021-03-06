// Copyright (c) 2016 Andreas Auernhammer. All rights reserved.
// Use of this source code is governed by a license that can be
// found in the LICENSE file.

// +build amd64,!gccgo,!appengine,!nacl

#include "textflag.h"

DATA ·sigma<>+0x00(SB)/4, $0x61707865
DATA ·sigma<>+0x04(SB)/4, $0x3320646e
DATA ·sigma<>+0x08(SB)/4, $0x79622d32
DATA ·sigma<>+0x0C(SB)/4, $0x6b206574
GLOBL ·sigma<>(SB), (NOPTR+RODATA), $16

DATA ·one<>+0x00(SB)/8, $1
DATA ·one<>+0x08(SB)/8, $0
GLOBL ·one<>(SB), (NOPTR+RODATA), $16

DATA ·rol16<>+0x00(SB)/8, $0x0504070601000302
DATA ·rol16<>+0x08(SB)/8, $0x0D0C0F0E09080B0A
GLOBL ·rol16<>(SB), (NOPTR+RODATA), $16

DATA ·rol8<>+0x00(SB)/8, $0x0605040702010003
DATA ·rol8<>+0x08(SB)/8, $0x0E0D0C0F0A09080B
GLOBL ·rol8<>(SB), (NOPTR+RODATA), $16

#define ROTL_SSE2(n, t, v) \
	MOVO  v, t;       \
	PSLLL $n, t;      \
	PSRLL $(32-n), v; \
	PXOR  t, v

#define CHACHA_QROUND_SSE2(v0, v1, v2, v3, t0) \
	PADDL v1, v0;          \
	PXOR  v0, v3;          \
	ROTL_SSE2(16, t0, v3); \
	PADDL v3, v2;          \
	PXOR  v2, v1;          \
	ROTL_SSE2(12, t0, v1); \
	PADDL v1, v0;          \
	PXOR  v0, v3;          \
	ROTL_SSE2(8, t0, v3);  \
	PADDL v3, v2;          \
	PXOR  v2, v1;          \
	ROTL_SSE2(7, t0, v1)

#define CHACHA_QROUND_SSSE3(v0, v1, v2, v3, t0, r16, r8) \
	PADDL  v1, v0;         \
	PXOR   v0, v3;         \
	PSHUFB r16, v3;        \
	PADDL  v3, v2;         \
	PXOR   v2, v1;         \
	ROTL_SSE2(12, t0, v1); \
	PADDL  v1, v0;         \
	PXOR   v0, v3;         \
	PSHUFB r8, v3;         \
	PADDL  v3, v2;         \
	PXOR   v2, v1;         \
	ROTL_SSE2(7, t0, v1)

#define CHACHA_SHUFFLE(v1, v2, v3) \
	PSHUFL $0x39, v1, v1; \
	PSHUFL $0x4E, v2, v2; \
	PSHUFL $0x93, v3, v3

#define XOR(dst, src, off, v0, v1, v2, v3, t0) \
	MOVOU 0+off(src), t0;  \
	PXOR  v0, t0;          \
	MOVOU t0, 0+off(dst);  \
	MOVOU 16+off(src), t0; \
	PXOR  v1, t0;          \
	MOVOU t0, 16+off(dst); \
	MOVOU 32+off(src), t0; \
	PXOR  v2, t0;          \
	MOVOU t0, 32+off(dst); \
	MOVOU 48+off(src), t0; \
	PXOR  v3, t0;          \
	MOVOU t0, 48+off(dst)

// func xorKeyStreamSSE2(dst, src []byte, block, state *[64]byte, rounds int) int
TEXT ·xorKeyStreamSSE2(SB), 4, $112-80
	MOVQ dst_base+0(FP), DI
	MOVQ src_base+24(FP), SI
	MOVQ src_len+32(FP), CX
	MOVQ block+48(FP), BX
	MOVQ state+56(FP), AX
	MOVQ rounds+64(FP), DX

	MOVQ SP, R9
	ADDQ $16, SP
	ANDQ $-16, SP

	MOVOU 0(AX), X0
	MOVOU 16(AX), X1
	MOVOU 32(AX), X2
	MOVOU 48(AX), X3
	MOVOU ·one<>(SB), X15

	TESTQ CX, CX
	JZ    done

	CMPQ CX, $64
	JBE  between_0_and_64

	CMPQ CX, $128
	JBE  between_64_and_128

	MOVO X0, 0(SP)
	MOVO X1, 16(SP)
	MOVO X2, 32(SP)
	MOVO X3, 48(SP)
	MOVO X15, 64(SP)

	CMPQ CX, $192
	JBE  between_128_and_192

	MOVQ $192, R14

at_least_256:
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	PADDQ 64(SP), X7
	MOVO  X0, X12
	MOVO  X1, X13
	MOVO  X2, X14
	MOVO  X7, X15
	PADDQ 64(SP), X15
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X15, X11
	PADDQ 64(SP), X11

	MOVQ DX, R8

chacha_loop_256:
	MOVO X8, 80(SP)
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X8)
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X8)
	MOVO 80(SP), X8

	MOVO X0, 80(SP)
	CHACHA_QROUND_SSE2(X12, X13, X14, X15, X0)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X0)
	MOVO 80(SP), X0

	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X13, X14, X15)
	CHACHA_SHUFFLE(X9, X10, X11)

	MOVO X8, 80(SP)
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X8)
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X8)
	MOVO 80(SP), X8

	MOVO X0, 80(SP)
	CHACHA_QROUND_SSE2(X12, X13, X14, X15, X0)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X0)
	MOVO 80(SP), X0

	CHACHA_SHUFFLE(X3, X2, X1)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X15, X14, X13)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_256

	MOVO X8, 80(SP)

	PADDL 0(SP), X0
	PADDL 16(SP), X1
	PADDL 32(SP), X2
	PADDL 48(SP), X3
	XOR(DI, SI, 0, X0, X1, X2, X3, X8)

	MOVO  0(SP), X0
	MOVO  16(SP), X1
	MOVO  32(SP), X2
	MOVO  48(SP), X3
	PADDQ 64(SP), X3

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ 64(SP), X3
	XOR(DI, SI, 64, X4, X5, X6, X7, X8)

	MOVO 64(SP), X5
	MOVO 80(SP), X8

	PADDL X0, X12
	PADDL X1, X13
	PADDL X2, X14
	PADDL X3, X15
	PADDQ X5, X3
	XOR(DI, SI, 128, X12, X13, X14, X15, X4)

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X5, X3

	CMPQ CX, $256
	JB   less_than_64

	XOR(DI, SI, 192, X8, X9, X10, X11, X4)
	MOVO X3, 48(SP)
	ADDQ $256, SI
	ADDQ $256, DI
	SUBQ $256, CX
	CMPQ CX, $192
	JA   at_least_256

	TESTQ CX, CX
	JZ    done
	MOVO  64(SP), X15
	CMPQ  CX, $64
	JBE   between_0_and_64
	CMPQ  CX, $128
	JBE   between_64_and_128

between_128_and_192:
	MOVQ  $128, R14
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	PADDQ X15, X7
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X7, X11
	PADDQ X15, X11

	MOVQ DX, R8

chacha_loop_192:
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X12)
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X12)
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X3, X2, X1)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_192

	PADDL 0(SP), X0
	PADDL 16(SP), X1
	PADDL 32(SP), X2
	PADDL 48(SP), X3
	XOR(DI, SI, 0, X0, X1, X2, X3, X12)

	MOVO  0(SP), X0
	MOVO  16(SP), X1
	MOVO  32(SP), X2
	MOVO  48(SP), X3
	PADDQ X15, X3

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ X15, X3
	XOR(DI, SI, 64, X4, X5, X6, X7, X12)

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3

	CMPQ CX, $192
	JB   less_than_64

	XOR(DI, SI, 128, X8, X9, X10, X11, X12)
	SUBQ $192, CX
	JMP  done

between_64_and_128:
	MOVQ  $64, R14
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X3, X11
	PADDQ X15, X11

	MOVQ DX, R8

chacha_loop_128:
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_128

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ X15, X3
	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3
	XOR(DI, SI, 0, X4, X5, X6, X7, X12)

	CMPQ CX, $128
	JB   less_than_64

	XOR(DI, SI, 64, X8, X9, X10, X11, X12)
	SUBQ $128, CX
	JMP  done

between_0_and_64:
	MOVQ $0, R14
	MOVO X0, X8
	MOVO X1, X9
	MOVO X2, X10
	MOVO X3, X11
	MOVQ DX, R8

chacha_loop_64:
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_64

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3
	CMPQ  CX, $64
	JB    less_than_64

	XOR(DI, SI, 0, X8, X9, X10, X11, X12)
	SUBQ $64, CX
	JMP  done

less_than_64:
	// R14 contains the num of bytes already xor'd
	ADDQ  R14, SI
	ADDQ  R14, DI
	SUBQ  R14, CX
	MOVOU X8, 0(BX)
	MOVOU X9, 16(BX)
	MOVOU X10, 32(BX)
	MOVOU X11, 48(BX)
	XORQ  R11, R11
	XORQ  R12, R12
	MOVQ  CX, BP

xor_loop:
	MOVB 0(SI), R11
	MOVB 0(BX), R12
	XORQ R11, R12
	MOVB R12, 0(DI)
	INCQ SI
	INCQ BX
	INCQ DI
	DECQ BP
	JA   xor_loop

done:
	MOVOU X3, 48(AX)
	MOVQ  R9, SP
	MOVQ  CX, ret+72(FP)
	RET

// func xorKeyStreamSSSE3(dst, src []byte, block, state *[64]byte, rounds int) int
TEXT ·xorKeyStreamSSSE3(SB), 4, $144-80
	MOVQ dst_base+0(FP), DI
	MOVQ src_base+24(FP), SI
	MOVQ src_len+32(FP), CX
	MOVQ block+48(FP), BX
	MOVQ state+56(FP), AX
	MOVQ rounds+64(FP), DX

	MOVQ SP, R9
	ADDQ $16, SP
	ANDQ $-16, SP

	MOVOU 0(AX), X0
	MOVOU 16(AX), X1
	MOVOU 32(AX), X2
	MOVOU 48(AX), X3
	MOVOU ·rol16<>(SB), X13
	MOVOU ·rol8<>(SB), X14
	MOVOU ·one<>(SB), X15

	TESTQ CX, CX
	JZ    done

	CMPQ CX, $64
	JBE  between_0_and_64

	CMPQ CX, $128
	JBE  between_64_and_128

	MOVO X0, 0(SP)
	MOVO X1, 16(SP)
	MOVO X2, 32(SP)
	MOVO X3, 48(SP)
	MOVO X15, 64(SP)

	CMPQ CX, $192
	JBE  between_128_and_192

	MOVO X13, 96(SP)
	MOVO X14, 112(SP)
	MOVQ $192, R14

at_least_256:
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	PADDQ 64(SP), X7
	MOVO  X0, X12
	MOVO  X1, X13
	MOVO  X2, X14
	MOVO  X7, X15
	PADDQ 64(SP), X15
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X15, X11
	PADDQ 64(SP), X11

	MOVQ DX, R8

chacha_loop_256:
	MOVO X8, 80(SP)
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X8, 96(SP), 112(SP))
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X8, 96(SP), 112(SP))
	MOVO 80(SP), X8

	MOVO X0, 80(SP)
	CHACHA_QROUND_SSSE3(X12, X13, X14, X15, X0, 96(SP), 112(SP))
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X0, 96(SP), 112(SP))
	MOVO 80(SP), X0

	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X13, X14, X15)
	CHACHA_SHUFFLE(X9, X10, X11)

	MOVO X8, 80(SP)
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X8, 96(SP), 112(SP))
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X8, 96(SP), 112(SP))
	MOVO 80(SP), X8

	MOVO X0, 80(SP)
	CHACHA_QROUND_SSSE3(X12, X13, X14, X15, X0, 96(SP), 112(SP))
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X0, 96(SP), 112(SP))
	MOVO 80(SP), X0

	CHACHA_SHUFFLE(X3, X2, X1)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X15, X14, X13)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_256

	MOVO X8, 80(SP)

	PADDL 0(SP), X0
	PADDL 16(SP), X1
	PADDL 32(SP), X2
	PADDL 48(SP), X3
	XOR(DI, SI, 0, X0, X1, X2, X3, X8)
	MOVO  0(SP), X0
	MOVO  16(SP), X1
	MOVO  32(SP), X2
	MOVO  48(SP), X3
	PADDQ 64(SP), X3

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ 64(SP), X3
	XOR(DI, SI, 64, X4, X5, X6, X7, X8)

	MOVO 64(SP), X5
	MOVO 80(SP), X8

	PADDL X0, X12
	PADDL X1, X13
	PADDL X2, X14
	PADDL X3, X15
	PADDQ X5, X3
	XOR(DI, SI, 128, X12, X13, X14, X15, X4)

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X5, X3

	CMPQ CX, $256
	JB   less_than_64

	XOR(DI, SI, 192, X8, X9, X10, X11, X4)
	MOVO X3, 48(SP)
	ADDQ $256, SI
	ADDQ $256, DI
	SUBQ $256, CX
	CMPQ CX, $192
	JA   at_least_256

	TESTQ CX, CX
	JZ    done
	MOVOU ·rol16<>(SB), X13
	MOVOU ·rol8<>(SB), X14
	MOVO  64(SP), X15
	CMPQ  CX, $64
	JBE   between_0_and_64
	CMPQ  CX, $128
	JBE   between_64_and_128

between_128_and_192:
	MOVQ  $128, R14
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	PADDQ X15, X7
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X7, X11
	PADDQ X15, X11

	MOVQ DX, R8

chacha_loop_192:
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X3, X2, X1)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_192

	PADDL 0(SP), X0
	PADDL 16(SP), X1
	PADDL 32(SP), X2
	PADDL 48(SP), X3
	XOR(DI, SI, 0, X0, X1, X2, X3, X12)

	MOVO  0(SP), X0
	MOVO  16(SP), X1
	MOVO  32(SP), X2
	MOVO  48(SP), X3
	PADDQ X15, X3

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ X15, X3
	XOR(DI, SI, 64, X4, X5, X6, X7, X12)

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3

	CMPQ CX, $192
	JB   less_than_64

	XOR(DI, SI, 128, X8, X9, X10, X11, X12)
	SUBQ $192, CX
	JMP  done

between_64_and_128:
	MOVQ  $64, R14
	MOVO  X0, X4
	MOVO  X1, X5
	MOVO  X2, X6
	MOVO  X3, X7
	MOVO  X0, X8
	MOVO  X1, X9
	MOVO  X2, X10
	MOVO  X3, X11
	PADDQ X15, X11

	MOVQ DX, R8

chacha_loop_128:
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X5, X6, X7)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X7, X6, X5)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_128

	PADDL X0, X4
	PADDL X1, X5
	PADDL X2, X6
	PADDL X3, X7
	PADDQ X15, X3
	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3
	XOR(DI, SI, 0, X4, X5, X6, X7, X12)

	CMPQ CX, $128
	JB   less_than_64

	XOR(DI, SI, 64, X8, X9, X10, X11, X12)
	SUBQ $128, CX
	JMP  done

between_0_and_64:
	MOVQ $0, R14
	MOVO X0, X8
	MOVO X1, X9
	MOVO X2, X10
	MOVO X3, X11
	MOVQ DX, R8

chacha_loop_64:
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X9, X10, X11)
	CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
	CHACHA_SHUFFLE(X11, X10, X9)
	SUBQ $2, R8
	JA   chacha_loop_64

	PADDL X0, X8
	PADDL X1, X9
	PADDL X2, X10
	PADDL X3, X11
	PADDQ X15, X3
	CMPQ  CX, $64
	JB    less_than_64

	XOR(DI, SI, 0, X8, X9, X10, X11, X12)
	SUBQ $64, CX
	JMP  done

less_than_64:
	// R14 contains the num of bytes already xor'd
	ADDQ  R14, SI
	ADDQ  R14, DI
	SUBQ  R14, CX
	MOVOU X8, 0(BX)
	MOVOU X9, 16(BX)
	MOVOU X10, 32(BX)
	MOVOU X11, 48(BX)
	XORQ  R11, R11
	XORQ  R12, R12
	MOVQ  CX, BP

xor_loop:
	MOVB 0(SI), R11
	MOVB 0(BX), R12
	XORQ R11, R12
	MOVB R12, 0(DI)
	INCQ SI
	INCQ BX
	INCQ DI
	DECQ BP
	JA   xor_loop

done:
	MOVQ  R9, SP
	MOVOU X3, 48(AX)
	MOVQ  CX, ret+72(FP)
	RET

// func supportsSSSE3() bool
TEXT ·supportsSSSE3(SB), NOSPLIT, $0-1
	XORQ AX, AX
	INCQ AX
	CPUID
	SHRQ $9, CX
	ANDQ $1, CX
	MOVB CX, ret+0(FP)
	RET

// func initialize(state *[64]byte, key []byte, nonce *[16]byte)
TEXT ·initialize(SB), 4, $0-40
	MOVQ state+0(FP), DI
	MOVQ key+8(FP), AX
	MOVQ nonce+32(FP), BX

	MOVOU ·sigma<>(SB), X0
	MOVOU 0(AX), X1
	MOVOU 16(AX), X2
	MOVOU 0(BX), X3

	MOVOU X0, 0(DI)
	MOVOU X1, 16(DI)
	MOVOU X2, 32(DI)
	MOVOU X3, 48(DI)
	RET

// func hChaCha20SSE2(out *[32]byte, nonce *[16]byte, key *[32]byte)
TEXT ·hChaCha20SSE2(SB), 4, $0-24
	MOVQ out+0(FP), DI
	MOVQ nonce+8(FP), AX
	MOVQ key+16(FP), BX

	MOVOU ·sigma<>(SB), X0
	MOVOU 0(BX), X1
	MOVOU 16(BX), X2
	MOVOU 0(AX), X3

	MOVQ $20, CX

chacha_loop:
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X4)
	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_QROUND_SSE2(X0, X1, X2, X3, X4)
	CHACHA_SHUFFLE(X3, X2, X1)
	SUBQ $2, CX
	JNZ  chacha_loop

	MOVOU X0, 0(DI)
	MOVOU X3, 16(DI)
	RET

// func hChaCha20SSSE3(out *[32]byte, nonce *[16]byte, key *[32]byte)
TEXT ·hChaCha20SSSE3(SB), 4, $0-24
	MOVQ out+0(FP), DI
	MOVQ nonce+8(FP), AX
	MOVQ key+16(FP), BX

	MOVOU ·sigma<>(SB), X0
	MOVOU 0(BX), X1
	MOVOU 16(BX), X2
	MOVOU 0(AX), X3
	MOVOU ·rol16<>(SB), X5
	MOVOU ·rol8<>(SB), X6

	MOVQ $20, CX

chacha_loop:
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X4, X5, X6)
	CHACHA_SHUFFLE(X1, X2, X3)
	CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X4, X5, X6)
	CHACHA_SHUFFLE(X3, X2, X1)
	SUBQ $2, CX
	JNZ  chacha_loop

	MOVOU X0, 0(DI)
	MOVOU X3, 16(DI)
	RET
