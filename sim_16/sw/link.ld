OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    imem (rx)  : ORIGIN = 0x00000000, LENGTH = 0x1000
    dmem (rwx) : ORIGIN = 0x10000000, LENGTH = 0x1000
}

_stack_start = ORIGIN(dmem) + LENGTH(dmem);
_stack_limit = _stack_start - 0x200;

SECTIONS
{
    .vectors :
    {
        . = ALIGN(4);
        KEEP(*(.vectors))
    } > imem

    .text :
    {
        . = ALIGN(4);
        _stext = .;
        *(.text)
        *(.text.*)
        *(.lit)
        *(.shdata)
        . = ALIGN(4);
        _etext = .;
    } > imem

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
        _image_end = .;
    } > imem

    /* The loader only initializes instruction SRAM. Writable initial data
       would require a CRT copy routine, so reject it below. */
    .data : AT(_image_end)
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        _edata = .;
    } > dmem

    /* 0x10000000..0x100000ff is reserved for FFT scratch/results. */
    .bss 0x10000100 (NOLOAD) :
    {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > dmem

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}

ASSERT(_image_end <= ORIGIN(imem) + LENGTH(imem),
       "FFT16 program exceeds the 4 KB instruction SRAM")
ASSERT(SIZEOF(.rodata) == 0,
       "instruction-SRAM data reads are unsupported; use immediate constants")
ASSERT(SIZEOF(.data) == 0,
       "initialized writable .data is unsupported by the SRAM loader")
ASSERT(_bss_end <= _stack_limit,
       "BSS overlaps the reserved 512-byte stack")
