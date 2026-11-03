// Links libwspr_ffi.a through include/wspr_ffi.h to check the C ABI.
// Run: ./tests/run_c_abi_test.sh
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include "wspr_ffi.h"

int main(void) {
  printf("wspr_ffi %s\n", wspr_ffi_version());
  assert(offsetof(WsprSpot, message_type) == 48);
  assert(wspr_message_type("EA4IQL IN80 37") == 1);
  assert(wspr_message_type("garbage text") == WSPR_ERR_INVALID_MESSAGE);

  const uint32_t rate = 48000;
  size_t n = wspr_transmission_samples(rate);
  float *tx = malloc(n * sizeof(float));
  size_t written = 0;
  assert(wspr_synthesize("EA4IQL IN80 37", 1520.0f, rate, tx, n, &written) == WSPR_OK);
  assert(written == n);

  size_t slot_len = 120 * rate;
  float *slot = calloc(slot_len, sizeof(float));
  for (size_t i = 0; i < n; i++) slot[rate + i] = 0.1f * tx[i];
  // light deterministic noise
  uint32_t x = 1;
  for (size_t i = 0; i < slot_len; i++) { x = x * 1664525u + 1013904223u; slot[i] += ((x >> 8) / 16777216.0f - 0.5f) * 0.05f; }

  WsprDecoder *dec = wspr_decoder_new();
  WsprSpot spots[8];
  size_t count = 0;
  int rc = wspr_decode(dec, slot, slot_len, rate, 0, spots, 8, &count);
  assert(rc == WSPR_OK);
  for (size_t i = 0; i < count; i++)
    printf("spot: '%s' type=%u pwr=%u f=%.2f dt=%.2f drift=%.3f snr=%.1f\n", spots[i].text,
           spots[i].message_type, spots[i].power_dbm, spots[i].freq_hz, spots[i].dt_s,
           spots[i].drift_hz_per_s, spots[i].snr_db);
  assert(count == 1 && strcmp(spots[0].text, "EA4IQL IN80 37") == 0);
  assert(wspr_decoder_known_callsigns(dec) >= 1);
  wspr_decoder_free(dec);
  free(tx); free(slot);
  printf("C ABI test OK\n");
  return 0;
}
