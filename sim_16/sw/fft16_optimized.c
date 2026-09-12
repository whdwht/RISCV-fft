#include "fft16_common.h"

static inline void optimized_twiddle(int k, int32_t odd_real,
                                     int32_t odd_imag, int32_t *result_real,
                                     int32_t *result_imag)
{
  switch (k) {
  case 0:
    *result_real = odd_real;
    *result_imag = odd_imag;
    break;
  case 2:
    *result_real = q10_shift(724 * (odd_real + odd_imag));
    *result_imag = q10_shift(724 * (odd_imag - odd_real));
    break;
  case 4:
    *result_real = odd_imag;
    *result_imag = -odd_real;
    break;
  case 6:
    *result_real = q10_shift(724 * (odd_imag - odd_real));
    *result_imag = q10_shift(-724 * (odd_imag + odd_real));
    break;
  case 1:
    *result_real = q10_shift(946 * odd_real + 392 * odd_imag);
    *result_imag = q10_shift(946 * odd_imag - 392 * odd_real);
    break;
  case 3:
    *result_real = q10_shift(392 * odd_real + 946 * odd_imag);
    *result_imag = q10_shift(392 * odd_imag - 946 * odd_real);
    break;
  case 5:
    *result_real = q10_shift(-392 * odd_real + 946 * odd_imag);
    *result_imag = q10_shift(-392 * odd_imag - 946 * odd_real);
    break;
  case 7:
    *result_real = q10_shift(-946 * odd_real + 392 * odd_imag);
    *result_imag = q10_shift(-946 * odd_imag - 392 * odd_real);
    break;
  default:
    /* k is constrained to 0..7 by the unrolled caller. */
    *result_real = 0;
    *result_imag = 0;
    break;
  }
}

int main(void)
{
  uint32_t even_words[FFT_INPUT_WORDS];
  int k;

  write_even_inputs();

#pragma GCC unroll 8
  for (k = 0; k < FFT_INPUT_WORDS; ++k)
    even_words[k] = fft_regs[FFT_OUTPUT_WORD_OFFSET + k];

  write_odd_inputs();

#pragma GCC unroll 8
  for (k = 0; k < FFT_INPUT_WORDS; ++k) {
    const uint32_t even_word = even_words[k];
    const uint32_t odd_word = fft_regs[FFT_OUTPUT_WORD_OFFSET + k];
    const int32_t even_real = unpack_real(even_word);
    const int32_t even_imag = unpack_imag(even_word);
    const int32_t odd_real = unpack_real(odd_word);
    const int32_t odd_imag = unpack_imag(odd_word);
    int32_t twiddled_real;
    int32_t twiddled_imag;

    optimized_twiddle(k, odd_real, odd_imag,
                      &twiddled_real, &twiddled_imag);
    store_fft16_pair(k, even_real, even_imag,
                     twiddled_real, twiddled_imag);
  }

  return 0;
}
