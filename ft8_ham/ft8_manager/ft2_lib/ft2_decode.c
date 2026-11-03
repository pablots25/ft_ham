// Copied from ft8_lib (https://github.com/kgoba/ft8_lib, MIT license) for FT2.
// ft8_lib stays unmodified. Keep this copy in sync with it when ft8_lib is updated.
// Only candidate search differs: FT4 sync with a wider time window. Decode the
// candidates with ft8_lib's ftx_decode_candidate.

#include "ft2_decode.h"
#include <ft8/constants.h>

#include <stdbool.h>

static void heapify_down(ftx_candidate_t heap[], int heap_size);
static void heapify_up(ftx_candidate_t heap[], int heap_size);

static const WF_ELEM_T* get_cand_mag(const ftx_waterfall_t* wf, const ftx_candidate_t* candidate)
{
    int offset = candidate->time_offset;
    offset = (offset * wf->time_osr) + candidate->time_sub;
    offset = (offset * wf->freq_osr) + candidate->freq_sub;
    offset = (offset * wf->num_bins) + candidate->freq_offset;
    return wf->mag + offset;
}

static int ft4_sync_score(const ftx_waterfall_t* wf, const ftx_candidate_t* candidate)
{
    int score = 0;
    int num_average = 0;

    // Get the pointer to symbol 0 of the candidate
    const WF_ELEM_T* mag_cand = get_cand_mag(wf, candidate);

    // Compute average score over sync symbols (block = 1-4, 34-37, 67-70, 100-103)
    for (int m = 0; m < FT4_NUM_SYNC; ++m)
    {
        for (int k = 0; k < FT4_LENGTH_SYNC; ++k)
        {
            int block = 1 + (FT4_SYNC_OFFSET * m) + k;
            int block_abs = candidate->time_offset + block;
            // Check for time boundaries
            if (block_abs < 0)
                continue;
            if (block_abs >= wf->num_blocks)
                break;

            // Get the pointer to symbol 'block' of the candidate
            const WF_ELEM_T* p4 = mag_cand + (block * wf->block_stride);

            int sm = kFT4_Costas_pattern[m][k]; // Index of the expected bin

            // score += (4 * p4[sm]) - p4[0] - p4[1] - p4[2] - p4[3];
            // num_average += 4;

            // Check only the neighbors of the expected symbol frequency- and time-wise
            if (sm > 0)
            {
                // look at one frequency bin lower
                score += WF_ELEM_MAG_INT(p4[sm]) - WF_ELEM_MAG_INT(p4[sm - 1]);
                ++num_average;
            }
            if (sm < 3)
            {
                // look at one frequency bin higher
                score += WF_ELEM_MAG_INT(p4[sm]) - WF_ELEM_MAG_INT(p4[sm + 1]);
                ++num_average;
            }
            if ((k > 0) && (block_abs > 0))
            {
                // look one symbol back in time
                score += WF_ELEM_MAG_INT(p4[sm]) - WF_ELEM_MAG_INT(p4[sm - wf->block_stride]);
                ++num_average;
            }
            if (((k + 1) < FT4_LENGTH_SYNC) && ((block_abs + 1) < wf->num_blocks))
            {
                // look one symbol forward in time
                score += WF_ELEM_MAG_INT(p4[sm]) - WF_ELEM_MAG_INT(p4[sm + wf->block_stride]);
                ++num_average;
            }
        }
    }

    if (num_average > 0)
        score /= num_average;

    return score;
}

int ft2_find_candidates(const ftx_waterfall_t* wf, int num_candidates, ftx_candidate_t heap[], int min_score)
{
    int (*sync_fun)(const ftx_waterfall_t*, const ftx_candidate_t*) = ft4_sync_score;
    const int num_tones = 4;

    // Time search range in symbols. FT2 symbols are 24 ms, so ft8_lib's
    // -10..+20 window would only cover -0.24..+0.48 s. Widen it so FT2 keeps
    // roughly the same tolerance in seconds (-0.48..+0.96 s) as FT4.
    const int min_time_offset = -20;
    const int max_time_offset = 40;

    int heap_size = 0;
    ftx_candidate_t candidate;

    // Here we allow time offsets that exceed signal boundaries, as long as we still have all data bits.
    // I.e. we can afford to skip the first 7 or the last 7 Costas symbols, as long as we track how many
    // sync symbols we included in the score, so the score is averaged.
    for (candidate.time_sub = 0; candidate.time_sub < wf->time_osr; ++candidate.time_sub)
    {
        for (candidate.freq_sub = 0; candidate.freq_sub < wf->freq_osr; ++candidate.freq_sub)
        {
            for (candidate.time_offset = min_time_offset; candidate.time_offset < max_time_offset; ++candidate.time_offset)
            {
                for (candidate.freq_offset = 0; (candidate.freq_offset + num_tones - 1) < wf->num_bins; ++candidate.freq_offset)
                {
                    candidate.score = sync_fun(wf, &candidate);

                    if (candidate.score < min_score)
                        continue;

                    // If the heap is full AND the current candidate is better than
                    // the worst in the heap, we remove the worst and make space
                    if ((heap_size == num_candidates) && (candidate.score > heap[0].score))
                    {
                        --heap_size;
                        heap[0] = heap[heap_size];
                        heapify_down(heap, heap_size);
                    }

                    // If there's free space in the heap, we add the current candidate
                    if (heap_size < num_candidates)
                    {
                        heap[heap_size] = candidate;
                        ++heap_size;
                        heapify_up(heap, heap_size);
                    }
                }
            }
        }
    }

    // Sort the candidates by sync strength - here we benefit from the heap structure
    int len_unsorted = heap_size;
    while (len_unsorted > 1)
    {
        // Take the top (index 0) element which is guaranteed to have the smallest score,
        // exchange it with the last element in the heap, and decrease the heap size.
        // Then restore the heap property in the new, smaller heap.
        // At the end the elements will be sorted in descending order.
        ftx_candidate_t tmp = heap[len_unsorted - 1];
        heap[len_unsorted - 1] = heap[0];
        heap[0] = tmp;
        len_unsorted--;
        heapify_down(heap, len_unsorted);
    }

    return heap_size;
}

static void heapify_down(ftx_candidate_t heap[], int heap_size)
{
    // heapify from the root down
    int current = 0; // root node
    while (true)
    {
        int left = 2 * current + 1;
        int right = left + 1;

        // Find the smallest value of (parent, left child, right child)
        int smallest = current;
        if ((left < heap_size) && (heap[left].score < heap[smallest].score))
        {
            smallest = left;
        }
        if ((right < heap_size) && (heap[right].score < heap[smallest].score))
        {
            smallest = right;
        }

        if (smallest == current)
        {
            break;
        }

        // Exchange the current node with the smallest child and move down to it
        ftx_candidate_t tmp = heap[smallest];
        heap[smallest] = heap[current];
        heap[current] = tmp;
        current = smallest;
    }
}

static void heapify_up(ftx_candidate_t heap[], int heap_size)
{
    // heapify from the last node up
    int current = heap_size - 1;
    while (current > 0)
    {
        int parent = (current - 1) / 2;
        if (!(heap[current].score < heap[parent].score))
        {
            break;
        }

        // Exchange the current node with its parent and move up
        ftx_candidate_t tmp = heap[parent];
        heap[parent] = heap[current];
        heap[current] = tmp;
        current = parent;
    }
}
