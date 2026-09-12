#include "fft16_common.h"

/* Keep this path deliberately generic so compiler-only and algorithmic
   improvements remain distinguishable in the benchmark. */
static __attribute__((noinline)) void merge_stored_pair(
    int k, int32_t cosine, int32_t sine)
{
  const uint32_t even_word = data_words[k];
  const uint32_t odd_word = data_words[FFT_INPUT_WORDS + k];
  const int32_t even_real = unpack_real(even_word);
  const int32_t even_imag = unpack_imag(even_word);
  const int32_t odd_real = unpack_real(odd_word);
  const int32_t odd_imag = unpack_imag(odd_word);
  const int32_t twiddled_real =
      q10_shift(cosine * odd_real + sine * odd_imag);
  const int32_t twiddled_imag =
      q10_shift(cosine * odd_imag - sine * odd_real);

  store_fft16_pair(k, even_real, even_imag,
                   twiddled_real, twiddled_imag);
}

int main(void)
{
  int k;

  write_even_inputs();
  for (k = 0; k < FFT_INPUT_WORDS; ++k)
    data_words[k] = fft_regs[FFT_OUTPUT_WORD_OFFSET + k];

  write_odd_inputs();
  for (k = 0; k < FFT_INPUT_WORDS; ++k)
    data_words[FFT_INPUT_WORDS + k] =
        fft_regs[FFT_OUTPUT_WORD_OFFSET + k];

  merge_stored_pair(0,  1024,   0);
  merge_stored_pair(1,   946, 392);
  merge_stored_pair(2,   724, 724);
  merge_stored_pair(3,   392, 946);
  merge_stored_pair(4,     0, 1024);
  merge_stored_pair(5,  -392, 946);
  merge_stored_pair(6,  -724, 724);
  merge_stored_pair(7,  -946, 392);

  return 0;
}
