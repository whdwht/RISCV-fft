.section .text
.text
.global main
.set FFT_BASE, 0x40000000
.set DATA_BASE, 0x10000000
main:
    # ============================================================
    # 16点FFT: 2次8点FFT(硬件加速核) + 软件合并级
    # 约定: x10=FFT基址, x20=data_sram基址
    # data_sram布局:
    #   0x00..0x1C  E[0..7]  (来自第1次8点FFT, 偶样本)
    #   0x20..0x3C  O[0..7]  (来自第2次8点FFT, 奇样本)
    #   0x40+8k/0x44+8k       X[k].re / X[k].im   (最终结果, 32位)
    #   0x80+8k/0x84+8k       X[k+8].re/ X[k+8].im
    # 复数打包: word = {re[31:16], im[15:0]}
    # ============================================================
    li   x10, FFT_BASE
    li   x20, DATA_BASE

    # ============================================================
    # Phase 1: 送8个偶样本 -> 读回 E[0..7]
    # 偶 lane m = x[2m]: idx 0,2,4,6,8,10,12,14
    # ============================================================
    li   t0, 0x2150013D        # x[0]  = ( 8528,   317)
    sw   t0, 0x00(x10)
    li   t0, 0x052FEFA1        # x[2]  = ( 1327, -4191)
    sw   t0, 0x04(x10)
    li   t0, 0xFF3DFF75        # x[4]  = ( -195,  -139)
    sw   t0, 0x08(x10)
    li   t0, 0x1A04E3A1        # x[6]  = ( 6660, -7263)
    sw   t0, 0x0C(x10)
    li   t0, 0x0BE704EF        # x[8]  = ( 3047,  1263)
    sw   t0, 0x10(x10)
    li   t0, 0x0EE7EDE3        # x[10] = ( 3815, -4637)
    sw   t0, 0x14(x10)
    li   t0, 0x10ACF9CB        # x[12] = ( 4268, -1589)
    sw   t0, 0x18(x10)
    li   t0, 0x0920152D        # x[14] = ( 2336,  5421)  <- 第8次写触发FFT
    sw   t0, 0x1C(x10)

    lw   t0, 0x20(x10)         # E[0]
    sw   t0, 0x00(x20)
    lw   t0, 0x24(x10)         # E[1]
    sw   t0, 0x04(x20)
    lw   t0, 0x28(x10)         # E[2]
    sw   t0, 0x08(x20)
    lw   t0, 0x2C(x10)         # E[3]
    sw   t0, 0x0C(x20)
    lw   t0, 0x30(x10)         # E[4]
    sw   t0, 0x10(x20)
    lw   t0, 0x34(x10)         # E[5]
    sw   t0, 0x14(x20)
    lw   t0, 0x38(x10)         # E[6]
    sw   t0, 0x18(x20)
    lw   t0, 0x3C(x10)         # E[7]
    sw   t0, 0x1C(x20)

    # ============================================================
    # Phase 2: 送8个奇样本 -> 读回 O[0..7]
    # 奇 lane m = x[2m+1]: idx 1,3,5,7,9,11,13,15
    # ============================================================
    li   t0, 0xED80E2B4        # x[1]  = (-4736, -7500)
    sw   t0, 0x00(x10)
    li   t0, 0x149A121B        # x[3]  = ( 5274,  4635)
    sw   t0, 0x04(x10)
    li   t0, 0x1143FF10        # x[5]  = ( 4419,  -240)
    sw   t0, 0x08(x10)
    li   t0, 0x077A1D4C        # x[7]  = ( 1914,  7500)
    sw   t0, 0x0C(x10)
    li   t0, 0xF62A0B9E        # x[9]  = (-2518,  2974)
    sw   t0, 0x10(x10)
    li   t0, 0xFA3F0925        # x[11] = (-1473,  2341)
    sw   t0, 0x14(x10)
    li   t0, 0xF4B30F4D        # x[13] = (-2893,  3917)
    sw   t0, 0x18(x10)
    li   t0, 0xF8DDF39A        # x[15] = (-1827, -3174) <- 触发FFT
    sw   t0, 0x1C(x10)

    lw   t0, 0x20(x10)         # O[0]
    sw   t0, 0x20(x20)
    lw   t0, 0x24(x10)         # O[1]
    sw   t0, 0x24(x20)
    lw   t0, 0x28(x10)         # O[2]
    sw   t0, 0x28(x20)
    lw   t0, 0x2C(x10)         # O[3]
    sw   t0, 0x2C(x20)
    lw   t0, 0x30(x10)         # O[4]
    sw   t0, 0x30(x20)
    lw   t0, 0x34(x10)         # O[5]
    sw   t0, 0x34(x20)
    lw   t0, 0x38(x10)         # O[6]
    sw   t0, 0x38(x20)
    lw   t0, 0x3C(x10)         # O[7]
    sw   t0, 0x3C(x20)

    # ============================================================
    # Phase 3: 合并级 (全展开, 无循环)
    # X[k]=E[k]+T,  X[k+8]=E[k]-T,  T = W16^k * O[k]
    # T_re=(c*O_re+s*O_im)>>10,  T_im=(c*O_im-s*O_re)>>10
    # 寄存器: t0=E词 t1=O词 t2=Ere t3=Eim t4=Ore t5=Oim
    #         t6=c s0=s a1a2=乘积 a3=Tre a4a5=乘积 a6=Tim
    #         s1=Xkre s2=Xkim s3=Xk8re s5=Xk8im
    # ============================================================

    # ---- k=0 : c=1024, s=0 ----
    lw   t0, 0x00(x20)
    lw   t1, 0x20(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, 1024
    li   s0, 0
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x40(x20)
    sw   s2, 0x44(x20)
    sw   s3, 0x80(x20)
    sw   s5, 0x84(x20)

    # ---- k=1 : c=946, s=392 ----
    lw   t0, 0x04(x20)
    lw   t1, 0x24(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, 946
    li   s0, 392
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x48(x20)
    sw   s2, 0x4C(x20)
    sw   s3, 0x88(x20)
    sw   s5, 0x8C(x20)

    # ---- k=2 : c=724, s=724 ----
    lw   t0, 0x08(x20)
    lw   t1, 0x28(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, 724
    li   s0, 724
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x50(x20)
    sw   s2, 0x54(x20)
    sw   s3, 0x90(x20)
    sw   s5, 0x94(x20)

    # ---- k=3 : c=392, s=946 ----
    lw   t0, 0x0C(x20)
    lw   t1, 0x2C(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, 392
    li   s0, 946
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x58(x20)
    sw   s2, 0x5C(x20)
    sw   s3, 0x98(x20)
    sw   s5, 0x9C(x20)

    # ---- k=4 : c=0, s=1024 ----
    lw   t0, 0x10(x20)
    lw   t1, 0x30(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, 0
    li   s0, 1024
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x60(x20)
    sw   s2, 0x64(x20)
    sw   s3, 0xA0(x20)
    sw   s5, 0xA4(x20)

    # ---- k=5 : c=-392, s=946 ----
    lw   t0, 0x14(x20)
    lw   t1, 0x34(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, -392
    li   s0, 946
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x68(x20)
    sw   s2, 0x6C(x20)
    sw   s3, 0xA8(x20)
    sw   s5, 0xAC(x20)

    # ---- k=6 : c=-724, s=724 ----
    lw   t0, 0x18(x20)
    lw   t1, 0x38(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, -724
    li   s0, 724
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x70(x20)
    sw   s2, 0x74(x20)
    sw   s3, 0xB0(x20)
    sw   s5, 0xB4(x20)

    # ---- k=7 : c=-946, s=392 ----
    lw   t0, 0x1C(x20)
    lw   t1, 0x3C(x20)
    srai t2, t0, 16
    slli t3, t0, 16
    srai t3, t3, 16
    srai t4, t1, 16
    slli t5, t1, 16
    srai t5, t5, 16
    li   t6, -946
    li   s0, 392
    mul  a1, t6, t4
    mul  a2, s0, t5
    add  a1, a1, a2
    srai a3, a1, 10
    mul  a4, t6, t5
    mul  a5, s0, t4
    sub  a4, a4, a5
    srai a6, a4, 10
    add  s1, t2, a3
    add  s2, t3, a6
    sub  s3, t2, a3
    sub  s5, t3, a6
    sw   s1, 0x78(x20)
    sw   s2, 0x7C(x20)
    sw   s3, 0xB8(x20)
    sw   s5, 0xBC(x20)

    # ============================================================
    # 完成. 16个结果已在 data_sram:
    #   X[k].re @ 0x10000040+8k, X[k].im @ 0x10000044+8k
    #   X[k+8].re@ 0x10000080+8k, X[k+8].im@ 0x10000084+8k  (k=0..7)
    # 死循环等仿真结束
    # ============================================================
end:
    j    end
