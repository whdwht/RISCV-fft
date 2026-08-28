.section .text              # 使用.section 伪操作指定text段，将接下来的代码汇编链接到text字段
.text  
.global main                # 使用.global 伪操作指定汇编程序入口       
main:
.set fft_ADDR           ,0x40000000
# test write x1,x2,x3
    # lui  x9,0x077a2
    # addi x9,x9,0x370
    la x9, 0x077a2370
    la x8, 0x1a04e3a1
    la x7, 0x1143ff10
    la x6, 0xff3dff75
    la x5, 0x149a121b
    la x4, 0x052fefa1
    la x3, 0xed80dda0
    la x2, 0x2150013d # 8528+317j 高16位实部，低16位虚部
    la x10, fft_ADDR
    sw x2, 0x00(x10)
    sw x3, 0x04(x10)
    sw x4, 0x08(x10)
    sw x5, 0x0C(x10)
    sw x6, 0x10(x10)
    sw x7, 0x14(x10)
    sw x8, 0x18(x10)
    sw x9, 0x1C(x10)
    lw x11, 0x20(x10)
    lw x12, 0x24(x10)
    lw x13, 0x28(x10)
    lw x14, 0x2c(x10)
    lw x15, 0x30(x10)
    lw x16, 0x34(x10)
    lw x17, 0x38(x10)
    lw x18, 0x3c(x10)
# x1: UART_ADDR,x2 : INST_ADDR
# lui x1, %hi(UART_ADDR)  
# addi x1,x1,%lo(UART_ADDR)
# lui x2, %hi(INST_ADDR)
# addi x2,x2,%lo(INST_ADDR)
# lui  x3, %hi(STAT)
# addi x3,x3,%lo(STAT)
