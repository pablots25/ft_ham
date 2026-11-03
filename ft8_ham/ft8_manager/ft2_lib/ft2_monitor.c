// Copied from ft8_lib (https://github.com/kgoba/ft8_lib, MIT license) for FT2.
// ft8_lib stays unmodified. Keep this copy in sync with it when ft8_lib is updated.
// Only monitor_init differs: FT2 timing. Use ft8_lib's monitor_process/reset/free.

#include "ft2_monitor.h"
#include "ft2_constants.h"
#include <common/common.h>

#define LOG_LEVEL LOG_INFO
#include <ft8/debug.h>

#include <stdlib.h>

static float hann_i(int i, int N)
{
    float x = sinf((float)M_PI * i / N);
    return x * x;
}

// static float hamming_i(int i, int N)
// {
//     const float a0 = (float)25 / 46;
//     const float a1 = 1 - a0;

//     float x1 = cosf(2 * (float)M_PI * i / N);
//     return a0 - a1 * x1;
// }

// static float blackman_i(int i, int N)
// {
//     const float alpha = 0.16f; // or 2860/18608
//     const float a0 = (1 - alpha) / 2;
//     const float a1 = 1.0f / 2;
//     const float a2 = alpha / 2;

//     float x1 = cosf(2 * (float)M_PI * i / N);
//     float x2 = 2 * x1 * x1 - 1; // Use double angle formula

//     return a0 - a1 * x1 + a2 * x2;
// }

static void waterfall_init(ftx_waterfall_t* me, int max_blocks, int num_bins, int time_osr, int freq_osr)
{
    size_t mag_size = max_blocks * time_osr * freq_osr * num_bins * sizeof(me->mag[0]);
    me->max_blocks = max_blocks;
    me->num_blocks = 0;
    me->num_bins = num_bins;
    me->time_osr = time_osr;
    me->freq_osr = freq_osr;
    me->block_stride = (time_osr * freq_osr * num_bins);
    me->mag = (WF_ELEM_T*)malloc(mag_size);
    LOG(LOG_DEBUG, "Waterfall size = %zu\n", mag_size);
}

static void waterfall_free(ftx_waterfall_t* me)
{
    free(me->mag);
}

void ft2_monitor_init(monitor_t* me, const monitor_config_t* cfg)
{
    const float slot_time = FT2_SLOT_TIME;
    const float symbol_period = FT2_SYMBOL_PERIOD;
    // Compute DSP parameters that depend on the sample rate
    me->block_size = (int)(cfg->sample_rate * symbol_period); // samples corresponding to one FSK symbol
    me->subblock_size = me->block_size / cfg->time_osr;
    me->nfft = me->block_size * cfg->freq_osr;
    me->fft_norm = 2.0f / me->nfft;
    // const int len_window = 1.8f * me->block_size; // hand-picked and optimized

    me->window = (float*)malloc(me->nfft * sizeof(me->window[0]));
    for (int i = 0; i < me->nfft; ++i)
    {
        // window[i] = 1;
        me->window[i] = me->fft_norm * hann_i(i, me->nfft);
        // me->window[i] = blackman_i(i, me->nfft);
        // me->window[i] = hamming_i(i, me->nfft);
        // me->window[i] = (i < len_window) ? hann_i(i, len_window) : 0;
    }
    me->last_frame = (float*)calloc(me->nfft, sizeof(me->last_frame[0]));

    LOG(LOG_INFO, "Block size = %d\n", me->block_size);
    LOG(LOG_INFO, "Subblock size = %d\n", me->subblock_size);

    size_t fft_work_size = 0;
    kiss_fftr_alloc(me->nfft, 0, 0, &fft_work_size);
    me->fft_work = malloc(fft_work_size);
    me->fft_cfg = kiss_fftr_alloc(me->nfft, 0, me->fft_work, &fft_work_size);

    LOG(LOG_INFO, "N_FFT = %d\n", me->nfft);
    LOG(LOG_DEBUG, "FFT work area = %zu\n", fft_work_size);

#ifdef WATERFALL_USE_PHASE
    me->nifft = 64; // Gives 200 Hz sample rate for FT8 (160ms symbol period)

    size_t ifft_work_size = 0;
    kiss_fft_alloc(me->nifft, 1, 0, &ifft_work_size);
    me->ifft_work = malloc(ifft_work_size);
    me->ifft_cfg = kiss_fft_alloc(me->nifft, 1, me->ifft_work, &ifft_work_size);

    LOG(LOG_INFO, "N_iFFT = %d\n", me->nifft);
    LOG(LOG_DEBUG, "iFFT work area = %zu\n", ifft_work_size);
#endif

    // Allocate enough blocks to fit the entire FT2 slot in memory
    const int max_blocks = (int)(slot_time / symbol_period);
    // Keep only FFT bins in the specified frequency range (f_min/f_max)
    me->min_bin = (int)(cfg->f_min * symbol_period);
    me->max_bin = (int)(cfg->f_max * symbol_period) + 1;
    const int num_bins = me->max_bin - me->min_bin;

    waterfall_init(&me->wf, max_blocks, num_bins, cfg->time_osr, cfg->freq_osr);
    // FT2 uses the FT4 frame layout, so ft8_lib treats the waterfall as FT4.
    me->wf.protocol = FTX_PROTOCOL_FT4;

    me->symbol_period = symbol_period;

    me->max_mag = -120.0f;
}
