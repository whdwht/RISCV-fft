#!/usr/bin/env bash
set -euo pipefail

usage="Usage: $0 ELF BIN VMEM STACK_USAGE READELF SHA_FILE"
elf_file="${1:?${usage}}"
bin_file="${2:?${usage}}"
vmem_file="${3:?${usage}}"
stack_usage_file="${4:?${usage}}"
readelf_bin="${5:?${usage}}"
sha_file="${6:?${usage}}"

for required in "${elf_file}" "${bin_file}" "${vmem_file}"; do
  if [[ ! -s "${required}" ]]; then
    echo "ERROR: missing or empty software artifact: ${required}" >&2
    exit 1
  fi
done

image_bytes="$(wc -c < "${bin_file}")"
if ((image_bytes > 4096)); then
  echo "ERROR: program image is ${image_bytes} bytes; instruction SRAM holds 4096" >&2
  exit 1
fi

attributes="$(${readelf_bin} -A "${elf_file}")"
arch="$(printf '%s\n' "${attributes}" | awk -F': ' '/Tag_RISCV_arch/ {print $2; exit}')"
if [[ -z "${arch}" || "${arch}" != *rv32i* || "${arch}" != *_m* || "${arch}" != *_c* ]]; then
  echo "ERROR: ELF does not advertise the required RV32I/M/C ISA: ${arch:-missing}" >&2
  exit 1
fi
if [[ "${arch}" == *_f* || "${arch}" == *_d* ]]; then
  echo "ERROR: ELF advertises an unsupported floating-point ISA: ${arch}" >&2
  exit 1
fi

data_size="$(${readelf_bin} -SW "${elf_file}" | awk '
  {
    for (field = 1; field <= NF; field++) {
      if ($field == ".data") {
        print ("0x" $(field + 4)) + 0
        found = 1
        exit
      }
    }
  }
  END {if (!found) print 0}
')"
if ((data_size != 0)); then
  echo "ERROR: initialized .data is not supported (size=${data_size})" >&2
  exit 1
fi

read -r rodata_addr rodata_size < <("${readelf_bin}" -SW "${elf_file}" | awk '
  {
    for (field = 1; field <= NF; field++) {
      if ($field == ".rodata") {
        print "0x" $(field + 2), "0x" $(field + 4)
        found = 1
        exit
      }
    }
  }
  END {if (!found) print 0, 0}
')
if ((rodata_size != 0)); then
  echo "ERROR: .rodata is unsupported because instruction-SRAM data reads do not complete" >&2
  exit 1
fi

max_stack=0
if [[ -s "${stack_usage_file}" ]]; then
  max_stack="$(awk -F'\t' 'NF >= 2 && $2 ~ /^[0-9]+$/ {if ($2 > max) max=$2} END {print max+0}' "${stack_usage_file}")"
fi
if ((max_stack > 512)); then
  echo "ERROR: a function needs ${max_stack} stack bytes; budget is 512" >&2
  exit 1
fi

{
  sha256sum "${elf_file}" "${bin_file}" "${vmem_file}"
  printf 'IMAGE_BYTES  %s\n' "${image_bytes}"
  printf 'MAX_FUNCTION_STACK_BYTES  %s\n' "${max_stack}"
  printf 'RISCV_ARCH  %s\n' "${arch}"
} > "${sha_file}"

echo "Software image passed: ${image_bytes}/4096 bytes, max function stack ${max_stack}/512 bytes, ${arch}"
