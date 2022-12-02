import operator
from itertools import groupby

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

# Slightly modified unique_justseen from https://docs.python.org/3/library/itertools.html
def uniq(iterable):
    '''List unique elements, preserving order. Remember only the element just seen.

    >>> ' '.join(uniq('AAAABBBCCDAABBB'))
    'A B C D A B'
    >>> ' '.join(uniq('ABBCCAD'))
    'A B C A D'
    '''
    return map(next, map(operator.itemgetter(1), groupby(iterable)))

async def out_values(dut):
    last = None
    while True:
        timeout = 10000
        while True:
            current = dut.top.io_out
            if current != last: break
            await ClockCycles(dut.clk, 1)
            timeout -= 1
            if timeout <= 0: raise Exception('Timeout waiting for out value change')

        last = current.value
        yield last

@cocotb.test()
async def test(dut):
    fib = list(uniq([ 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 121 ]))[::-1]

    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut._log.info("reset")
    dut.rst.value = 1
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 0

    dut._log.info("check fibonacci output")
    async for i in out_values(dut):
        dut._log.info(f"out {i.value}")
        val = fib.pop()
        dut._log.info(f"should be {val}")

        assert val == i.value
    #for i in range(100):
    #    await ClockCycles(dut.clk, 1)

        dut._log.info(f"---------------")
        for var in [
                dut.top.m.a.value,
                dut.top.m.b.value,
                dut.top.m.pc.value,
                dut.top.m.out_reg_instr,
                dut.top.m.mc.count,
                dut.top.m.instr_decode.address,
                dut.top.m.micro,
                dut.top.m.micro_done,
                dut.top.io_out,
                dut.top.halted,
        ]:
            dut._log.info(f"   {(var._path+':').ljust(25)}{var.value} / {int(var.value)} / {hex(var.value)}")

        if len(fib) == 0: break
