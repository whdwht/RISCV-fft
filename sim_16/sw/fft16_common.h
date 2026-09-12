#ifndef FFT16_COMMON_H
#define FFT16_COMMON_H

typedef signed short int int16_t;
typedef signed int int32_t;
typedef unsigned int uint32_t;

typedef char fft16_requires_16_bit_short[(sizeof(int16_t) == 2) ? 1 : -1];
typedef char fft16_requires_32_bit_int[(sizeof(int32_t) == 4) ? 1 : -1];

enum {
  FFT_INPUT_WORDS = 8,
  FFT_OUTPUT_WORD_OFFSET = 8,
  RESULT_WORD_OFFSET = 16,
  RESULT_UPPER_WORD_OFFSET = 32,
  Q10_SHIFT = 10
};

#define FFT_BASE_ADDRESS  0x40000000u
#define DATA_BASE_ADDRESS 0x10000000u

/*
 * Do not turn these into static const pointer objects.  At -O0 GCC emits
 * such objects into .rodata, but this SoC cannot reliably complete data-port
 * reads from instruction SRAM.  Macros always materialize the MMIO bases as
 * immediates instead.
 */
#define fft_regs  ((volatile uint32_t *)FFT_BASE_ADDRESS)
#define data_words ((volatile uint32_t *)DATA_BASE_ADDRESS)

static inline void write_even_inputs(void)
{
  fft_regs[0] = 0x2150013du;
  fft_regs[1] = 0x052fefa1u;
  fft_regs[2] = 0xff3dff75u;
  fft_regs[3] = 0x1a04e3a1u;
  fft_regs[4] = 0x0be704efu;
  fft_regs[5] = 0x0ee7ede3u;
  fft_regs[6] = 0x10acf9cbu;
  fft_regs[7] = 0x0920152du;
}

static inline void write_odd_inputs(void)
{
  fft_regs[0] = 0xed80e2b4u;
  fft_regs[1] = 0x149a121bu;
  fft_regs[2] = 0x1143ff10u;
  fft_regs[3] = 0x077a1d4cu;
  fft_regs[4] = 0xf62a0b9eu;
  fft_regs[5] = 0xfa3f0925u;
  fft_regs[6] = 0xf4b30f4du;
  fft_regs[7] = 0xf8ddf39au;
}

static inline int32_t unpack_real(uint32_t packed)
{
  return (int32_t)(int16_t)(packed >> 16);
}

static inline int32_t unpack_imag(uint32_t packed)
{
  return (int32_t)(int16_t)(packed & 0xffffu);
}

static inline int32_t q10_shift(int32_t value)
{
  /* GCC for RV32 lowers signed right shift to SRA/SRAI, matching gcc.s. */
  return value >> Q10_SHIFT;
}

static inline void store_fft16_pair(int k, int32_t even_real,
                                    int32_t even_imag, int32_t twiddled_real,
                                    int32_t twiddled_imag)
{
  const int lower = RESULT_WORD_OFFSET + 2 * k;
  const int upper = RESULT_UPPER_WORD_OFFSET + 2 * k;

  data_words[lower] = (uint32_t)(even_real + twiddled_real);
  data_words[lower + 1] = (uint32_t)(even_imag + twiddled_imag);
  data_words[upper] = (uint32_t)(even_real - twiddled_real);
  data_words[upper + 1] = (uint32_t)(even_imag - twiddled_imag);
}

#endif
