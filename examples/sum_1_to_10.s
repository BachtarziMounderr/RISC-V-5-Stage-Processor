# RV32I subset example. The result 55 is stored at data address 0.
# x1 = loop counter, x2 = limit, x3 = accumulator, x4 = readback.

    addi x1, x0, 1
    addi x2, x0, 11
    addi x3, x0, 0
loop:
    add  x3, x3, x1
    addi x1, x1, 1
    bne  x1, x2, loop
    sw   x3, 0(x0)
    lw   x4, 0(x0)
