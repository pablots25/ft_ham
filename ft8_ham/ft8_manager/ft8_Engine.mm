#import "ft8_Engine.h"

#include "decode.h"
#include "encode.h"
#include "monitor.h"

#import <AVFoundation/AVFoundation.h>
#include <Accelerate/Accelerate.h>
#define CALLSIGN_HASHTABLE_SIZE 256

// -----------------------------------------------------------------------------
// MARK: - Local Callsign Hash Table
// -----------------------------------------------------------------------------
static struct {
  char callsign[12];
  uint32_t hash;
} callsign_hashtable[CALLSIGN_HASHTABLE_SIZE];

static int callsign_hashtable_size;

void hashtable_init(void) {
  callsign_hashtable_size = 0;
  memset(callsign_hashtable, 0, sizeof(callsign_hashtable));
}

void hashtable_cleanup(uint8_t max_age) {
  for (int i = 0; i < CALLSIGN_HASHTABLE_SIZE; ++i) {
    if (callsign_hashtable[i].callsign[0] != '\0') {
      uint8_t age = (uint8_t)(callsign_hashtable[i].hash >> 24);
      if (age > max_age) {
        callsign_hashtable[i].callsign[0] = '\0';
        callsign_hashtable[i].hash = 0;
        callsign_hashtable_size--;
      } else {
        callsign_hashtable[i].hash = (((uint32_t)age + 1u) << 24) |
                                     (callsign_hashtable[i].hash & 0x3FFFFFu);
      }
    }
  }
}

void hashtable_add(const char *callsign, uint32_t hash) {
  uint16_t hash10 = (hash >> 12) & 0x3FFu;
  int idx = (hash10 * 23) % CALLSIGN_HASHTABLE_SIZE;

  while (callsign_hashtable[idx].callsign[0] != '\0') {
    if (((callsign_hashtable[idx].hash & 0x3FFFFFu) == hash) &&
        (strcmp(callsign_hashtable[idx].callsign, callsign) == 0)) {
      callsign_hashtable[idx].hash &= 0x3FFFFFu;
      return;
    } else {
      idx = (idx + 1) % CALLSIGN_HASHTABLE_SIZE;
    }
  }

  callsign_hashtable_size++;
  strncpy(callsign_hashtable[idx].callsign, callsign, 11);
  callsign_hashtable[idx].callsign[11] = '\0';
  callsign_hashtable[idx].hash = hash;
}

bool hashtable_lookup(ftx_callsign_hash_type_t hash_type, uint32_t hash,
                      char *callsign) {
  uint8_t hash_shift = (hash_type == FTX_CALLSIGN_HASH_10_BITS)
                           ? 12
                           : (hash_type == FTX_CALLSIGN_HASH_12_BITS ? 10 : 0);
  uint16_t hash10 = (hash >> (12 - hash_shift)) & 0x3FFu;
  int idx = (hash10 * 23) % CALLSIGN_HASHTABLE_SIZE;

  while (callsign_hashtable[idx].callsign[0] != '\0') {
    if (((callsign_hashtable[idx].hash & 0x3FFFFFu) >> hash_shift) == hash) {
      strcpy(callsign, callsign_hashtable[idx].callsign);
      return true;
    }
    idx = (idx + 1) % CALLSIGN_HASHTABLE_SIZE;
  }

  callsign[0] = '\0';
  return false;
}

// Interface used by ftx_message_decode()
static ftx_callsign_hash_interface_t hash_if = {.lookup_hash = hashtable_lookup,
                                                .save_hash = hashtable_add};

// -----------------------------------------------------------------------------
// MARK: - FT8 Engine Implementation
// -----------------------------------------------------------------------------
@interface ft8_Engine ()
@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, strong) AVAudioInputNode *inputNode;
@property(nonatomic, strong) NSMutableData *audioBuffer;
@property(nonatomic, strong) dispatch_queue_t audioQueue;
@property(nonatomic, assign) double sampleRate;
@property(nonatomic, assign) BOOL isCapturing;
@property(nonatomic, assign) monitor_t mon;
@property(nonatomic, assign) BOOL monitorInitialized;

// Reusable date formatter for logging
@property(nonatomic, strong) NSDateFormatter *logDateFormatter;
@end

@implementation ft8_Engine

- (instancetype)init {
  self = [super init];
  if (self) {
    _audioEngine = [[AVAudioEngine alloc] init];
    _audioQueue =
        dispatch_queue_create("ft8.audioQueue", DISPATCH_QUEUE_SERIAL);
    _monitorInitialized = NO;

    // Initialize reusable date formatter
    _logDateFormatter = [[NSDateFormatter alloc] init];
    [_logDateFormatter
        setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [_logDateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
  }
  return self;
}

// -----------------------------------------------------------------------------
// MARK: - Centralized Logger
// -----------------------------------------------------------------------------
- (void)logFT8:(NSString *)format, ... {
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  NSString *ts;
  @synchronized(self.logDateFormatter) {
    ts = [self.logDateFormatter stringFromDate:[NSDate date]];
  }

  NSLog(@"[%@] [FT8] %@", ts, message);
}

#pragma mark - Universal Interface

- (NSArray<NSDictionary *> *)decode:(nullable NSURL *)input isFT4:(BOOL)isFT4 {
#if TARGET_OS_SIMULATOR
  if (input) {
    NSLog(@"[FT8] Decoding WAV (Simulator)");
    return [self decodeFromWAV:input isFT4:isFT4];
  } else {
    NSLog(@"[FT8] Simulator without input file: microphone not available.");
    return @[];
  }
#else
  if (input) {
    NSLog(@"[FT8] Decoding WAV (Device)");
    return [self decodeFromWAV:input isFT4:isFT4];
  } else {
    NSLog(@"[FT8] Decoding in real-time from microphone");
    return [self decodeFromMic:isFT4];
  }
#endif
}

#pragma mark - Decoding from WAV File

- (NSArray<NSDictionary *> *)decodeFromWAV:(NSURL *)wavURL isFT4:(BOOL)isFT4 {
  NSError *error = nil;
  AVAudioFile *file = [[AVAudioFile alloc] initForReading:wavURL error:&error];
  if (error) {
    [self logFT8:@"Error opening WAV: %@", error];
    return @[];
  }

  AVAudioFormat *format = file.processingFormat;
  AVAudioFrameCount frameCount = (AVAudioFrameCount)file.length;
  AVAudioPCMBuffer *buffer =
      [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                    frameCapacity:frameCount];
  [file readIntoBuffer:buffer error:&error];
  if (error) {
    [self logFT8:@"Error reading WAV: %@", error];
    return @[];
  }

  NSData *audioData = [NSData dataWithBytes:buffer.floatChannelData[0]
                                     length:buffer.frameLength * sizeof(float)];
  return [self decodeBufferUsingMonitor:audioData
                             sampleRate:format.sampleRate
                                  isFT4:isFT4];
}

#pragma mark - Real-time Decoding from Microphone

- (NSArray<NSDictionary *> *)decodeFromMic:(BOOL)isFT4 {
  AVAudioInputNode *inputNode = _audioEngine.inputNode;
  AVAudioFormat *inputFormat = [inputNode inputFormatForBus:0];
  if (inputFormat.sampleRate <= 0 || inputFormat.channelCount <= 0) {
    [self logFT8:@"Invalid input format: sampleRate=%.1f channels=%u",
                 inputFormat.sampleRate, inputFormat.channelCount];
    self.isCapturing = NO;
    return @[];
  }

  NSMutableArray *decodedMessages = [NSMutableArray array];

  [inputNode installTapOnBus:0
                  bufferSize:1024
                      format:inputFormat
                       block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
                         NSData *audioData = [NSData
                             dataWithBytes:buffer.floatChannelData[0]
                                    length:buffer.frameLength * sizeof(float)];
                         NSArray *msgs = [self
                             decodeBufferUsingMonitor:audioData
                                           sampleRate:inputFormat.sampleRate
                                                isFT4:isFT4];
                         if (msgs.count > 0) {
                           [decodedMessages addObjectsFromArray:msgs];
                         }
                       }];

  NSError *error = nil;
  [_audioEngine startAndReturnError:&error];
  if (error) {
    [self logFT8:@"Error starting audio engine: %@", error];
    return @[];
  }

  [self logFT8:@"Real-time decoding started..."];
  return decodedMessages;
}

#pragma mark - Real-time Decoding

- (void)startRealtimeDecode:(BOOL)isFT4
             messageHandler:
                 (void (^)(NSArray<NSDictionary *> *messages))handler {
  if (self.isCapturing)
    return;
  self.isCapturing = YES;

  // AVAudioSession setup
  NSError *sessionError = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayAndRecord
           withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                       AVAudioSessionCategoryOptionAllowBluetoothHFP
                 error:&sessionError];
  [session setMode:AVAudioSessionModeMeasurement error:&sessionError];
  [session setPreferredSampleRate:12000 error:&sessionError];
  [session setActive:YES error:&sessionError];

  if (sessionError) {
    [self logFT8:@"Error configuring AVAudioSession: %@", sessionError];
    self.isCapturing = NO;
    return;
  }

  self.audioEngine = [[AVAudioEngine alloc] init];
  self.inputNode = self.audioEngine.inputNode;

  AVAudioFormat *inputFormat = [self.inputNode inputFormatForBus:0];
  self.sampleRate =
      (inputFormat.sampleRate > 0) ? inputFormat.sampleRate : 12000;
  [self logFT8:@"Capture started (%.1f Hz)", self.sampleRate];

  self.audioBuffer = [NSMutableData data];

  double slotTime = isFT4 ? FT4_SLOT_TIME : FT8_SLOT_TIME;

  AVAudioFormat *desiredFormat =
      [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                       sampleRate:self.sampleRate
                                         channels:1
                                      interleaved:NO];

  [self.inputNode removeTapOnBus:0];

  __block BOOL firstSlotPartialSent = NO;

  [self.inputNode
      installTapOnBus:0
           bufferSize:2048
               format:desiredFormat
                block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                  if (!buffer.floatChannelData)
                    return;
                  float *data = buffer.floatChannelData[0];
                  NSUInteger count = buffer.frameLength;

                  dispatch_async(self.audioQueue, ^{
                    [self.audioBuffer appendBytes:data
                                           length:count * sizeof(float)];

                    NSUInteger samplesPerSlot =
                        (NSUInteger)(slotTime * self.sampleRate);

                    // Primer slot parcial
                    if (!firstSlotPartialSent &&
                        self.audioBuffer.length / sizeof(float) <
                            samplesPerSlot) {
                      firstSlotPartialSent = YES;
                      if (handler) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                          [self logFT8:@"Partial slot: length: %lu samples",
                                       (unsigned long)(self.audioBuffer.length /
                                                       sizeof(float))];
                          handler(@[ @{
                            @"text" : @"Partial slot",
                            @"snr" : @0,
                            @"timeDelta" : @0,
                            @"frequency" : @0,
                            @"ldpc_errors" : @0,
                            @"timestamp" :
                                @([[NSDate date] timeIntervalSince1970])
                          } ]);
                        });
                      }
                    }

                    // Slots completos
                    while (self.audioBuffer.length / sizeof(float) >=
                           samplesPerSlot) {
                      NSData *slotData = [self.audioBuffer
                          subdataWithRange:NSMakeRange(0, samplesPerSlot *
                                                              sizeof(float))];
                      [self.audioBuffer
                          replaceBytesInRange:NSMakeRange(0, samplesPerSlot *
                                                                 sizeof(float))
                                    withBytes:NULL
                                       length:0];

                      dispatch_async(
                          dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,
                                                    0),
                          ^{
                            NSArray<NSDictionary *> *msgs =
                                [self decodeBufferUsingMonitor:slotData
                                                    sampleRate:self.sampleRate
                                                         isFT4:isFT4];

                            if (handler) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                [self logFT8:@"Decoded slot, messages: %lu",
                                             (unsigned long)msgs.count];
                                handler(msgs ?: @[]);
                              });
                            }
                          });
                    }
                  });
                }];

  [self.audioEngine prepare];
  NSError *error = nil;
  [self.audioEngine startAndReturnError:&error];
  if (error) {
    [self logFT8:@"Error starting AVAudioEngine: %@", error];
    self.isCapturing = NO;
  }
}

- (void)stopRealtimeDecode {
  if (!self.isCapturing)
    return;
  [self.inputNode removeTapOnBus:0];
  [self.audioEngine stop];
  self.isCapturing = NO;
  [self logFT8:@"Capture stopped"];
}

#pragma mark - Decoding with Monitor (FT8 / FT4)

- (NSArray<NSDictionary *> *)decodeBufferUsingMonitor:(NSData *)audioData
                                           sampleRate:(double)sampleRate
                                                isFT4:(BOOL)isFT4 {
  const float *audio = (const float *)audioData.bytes;
  NSUInteger nSamples = audioData.length / sizeof(float);
  ftx_protocol_t protocol = isFT4 ? FTX_PROTOCOL_FT4 : FTX_PROTOCOL_FT8;

  monitor_t mon;
  monitor_config_t cfg = {.f_min = 200,
                          .f_max = 3000,
                          .sample_rate = (int)sampleRate,
                          .time_osr = 2,
                          .freq_osr = 2,
                          .protocol = protocol};

  hashtable_init();
  monitor_init(&mon, &cfg);

  int blockSize = mon.block_size;
  for (int pos = 0; pos + blockSize <= nSamples; pos += blockSize) {
    monitor_process(&mon, audio + pos);
  }

  const ftx_waterfall_t *wf = &mon.wf;

  // ------------------------------------------------------------
  // Find candidates
  // ------------------------------------------------------------
  ftx_candidate_t candidates[140];
  int nCand = ftx_find_candidates(wf, 140, candidates, 10);

  NSMutableArray<NSDictionary *> *results = [NSMutableArray array];

  for (int i = 0; i < nCand; i++) {
    ftx_message_t msg;
    ftx_decode_status_t status;
    if (ftx_decode_candidate(wf, &candidates[i], 25, &msg, &status)) {
      char text[FTX_MAX_MESSAGE_LENGTH];
      ftx_message_offsets_t offsets;
      ftx_message_rc_t rc = ftx_message_decode(&msg, &hash_if, text, &offsets);

      if (rc == FTX_MESSAGE_RC_OK) {
        float snr = compute_snr_db(wf, &candidates[i]);
        float symbolPeriod = isFT4 ? FT4_SYMBOL_PERIOD : FT8_SYMBOL_PERIOD;

        float timeSec = (candidates[i].time_offset +
                         (float)candidates[i].time_sub / wf->time_osr) *
                        symbolPeriod;
        float freqHz = (mon.min_bin + candidates[i].freq_offset +
                        (float)candidates[i].freq_sub / wf->freq_osr) /
                       symbolPeriod;

        NSDate *now = [NSDate date]; // current date and time
        NSTimeInterval timestamp =
            [now timeIntervalSince1970]; // seconds since 1970

        NSDictionary *msgDict = @{
          @"text" : [NSString stringWithUTF8String:text],
          @"snr" : @(snr),
          @"timeDelta" : @(timeSec),
          @"time" : @(timeSec),
          @"frequency" : @(freqHz),
          @"ldpc_errors" : @(status.ldpc_errors),
          @"ldpcErrors" : @(status.ldpc_errors),
          @"timestamp" : @(timestamp)
        };
        [results addObject:msgDict];
      }
    }
  }

  monitor_free(&mon);
  hashtable_cleanup(10);

  NSMutableDictionary<NSString *, NSDictionary *> *bestResults =
      [NSMutableDictionary dictionary];
  for (NSDictionary *msg in results) {
    NSString *text = msg[@"text"];
    double snr = [msg[@"snr"] doubleValue];

    NSDictionary *existing = bestResults[text];
    if (!existing || snr > [existing[@"snr"] doubleValue]) {
      bestResults[text] = msg;
    }
  }

    // Check for partial signal
    double signalDuration = isFT4 ? 4.5 : 12.6;   // physical signal length
    double decodeMargin   = isFT4 ? 0.1 : 0.2;    // safety margin

    double minSamplesForFullSignal =
        (signalDuration + decodeMargin) * sampleRate;

    // Only report partial slot if we could not decode any valid messages
    if (nSamples < minSamplesForFullSignal && bestResults.count == 0) {
        [bestResults setObject:@{
            @"text" : @"Partial slot",
            @"snr" : @0,
            @"timeDelta" : @0,
            @"frequency" : @0,
            @"ldpc_errors" : @0,
            @"timestamp" : @([[NSDate date] timeIntervalSince1970])
        }
                        forKey:@"Partial slot"];
    }

  return bestResults.allValues;
}

// -----------------------------------------------------------------------------
// MARK: - FT8/FT4 Signal Generation (WAV and NSData)
// -----------------------------------------------------------------------------

#pragma mark - GFSK Synthesis Helper

- (void)synthGFSK:(const uint8_t *)symbols
             nSym:(int)n_sym
               f0:(float)f0
         symbolBT:(float)symbol_bt
     symbolPeriod:(float)symbol_period
       sampleRate:(int)sampleRate
           output:(float *)output {
  int n_spsym = (int)(0.5f + sampleRate * symbol_period);
  int n_wave = n_sym * n_spsym;
  float hmod = 1.0f;
  float dphi_peak = 2 * M_PI * hmod / n_spsym;

  std::vector<float> dphi(n_wave + 2 * n_spsym, 2 * M_PI * f0 / sampleRate);
  std::vector<float> pulse(3 * n_spsym);

  // GFSK pulse
  const float K = (float)(M_PI * sqrt(2.0 / log(2.0)));
  for (int i = 0; i < 3 * n_spsym; ++i) {
    float t = i / (float)n_spsym - 1.5f;
    float arg1 = K * symbol_bt * (t + 0.5f);
    float arg2 = K * symbol_bt * (t - 0.5f);
    pulse[i] = (erff(arg1) - erff(arg2)) / 2;
  }

  for (int i = 0; i < n_sym; ++i) {
    int ib = i * n_spsym;
    for (int j = 0; j < 3 * n_spsym; ++j) {
      dphi[j + ib] += dphi_peak * symbols[i] * pulse[j];
    }
  }

  for (int j = 0; j < 2 * n_spsym; ++j) {
    dphi[j] += dphi_peak * pulse[j + n_spsym] * symbols[0];
    dphi[j + n_sym * n_spsym] += dphi_peak * pulse[j] * symbols[n_sym - 1];
  }

  float phi = 0;
  for (int k = 0; k < n_wave; ++k) {
    output[k] = sinf(phi);
    phi = fmodf(phi + dphi[k + n_spsym], 2 * M_PI);
  }

  int n_ramp = n_spsym / 8;
  for (int i = 0; i < n_ramp; ++i) {
    float env = (1 - cosf(2 * M_PI * i / (2 * n_ramp))) / 2;
    output[i] *= env;
    output[n_wave - 1 - i] *= env;
  }
}

#pragma mark - FT8/FT4 Signal Generation

- (NSData *)generateFT8:(NSString *)message
              frequency:(float)frequency
                  isFT4:(BOOL)isFT4
                 toFile:(nullable NSURL *)outputURL {
  // Encode message
  ftx_message_t ftxMsg;
  ftx_message_rc_t rc = ftx_message_encode(&ftxMsg, NULL, [message UTF8String]);
  if (rc != FTX_MESSAGE_RC_OK) {
    [self logFT8:@"Error packing message (%d)", rc];
    return nil;
  }

  int numTones = isFT4 ? FT4_NN : FT8_NN;
  float symbolPeriod = isFT4 ? FT4_SYMBOL_PERIOD : FT8_SYMBOL_PERIOD;
  float symbolBT = isFT4 ? 1.0f : 2.0f;
  float slotTime = isFT4 ? FT4_SLOT_TIME : FT8_SLOT_TIME;
  int sampleRate = 12000;

  uint8_t tones[numTones];
  if (isFT4) {
    ft4_encode(ftxMsg.payload, tones);
  } else {
    ft8_encode(ftxMsg.payload, tones);
  }

  int nSpsym = (int)(0.5f + sampleRate * symbolPeriod);
  int nSamples = numTones * nSpsym;
  int nSilence = (int)(0.1 * (slotTime * sampleRate - nSamples));
  int nTotal = nSamples + 2 * nSilence;

  NSMutableData *signalData =
      [NSMutableData dataWithLength:nTotal * sizeof(float)];
  float *signal = (float *)signalData.mutableBytes;
  memset(signal, 0, nTotal * sizeof(float));

  // Use refactored GFSK synthesis
  [self synthGFSK:tones
              nSym:numTones
                f0:frequency
          symbolBT:symbolBT
      symbolPeriod:symbolPeriod
        sampleRate:sampleRate
            output:signal + nSilence];

  // If output file is requested, save WAV
  if (outputURL) {
    AVAudioFormat *format =
        [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate
                                                       channels:1];
    AVAudioPCMBuffer *pcmBuffer =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                      frameCapacity:nTotal];
    pcmBuffer.frameLength = nTotal;
    memcpy(pcmBuffer.floatChannelData[0], signal, nTotal * sizeof(float));

    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForWriting:outputURL
                                                   settings:format.settings
                                                      error:&error];
    if (error) {
      [self logFT8:@"Error creating WAV: %@", error];
      return nil;
    }

    [file writeFromBuffer:pcmBuffer error:&error];
    if (error) {
      [self logFT8:@"Error writing WAV: %@", error];
      return nil;
    }

    [self logFT8:@"WAV file generated at %@", outputURL.path];
  }

  // Always return NSData buffer
  return signalData;
}

/// Compute SNR estimate from the candidate's sync score.
/// The sync score from Costas array correlation is a reliable proxy for SNR.
/// Based on the reference ft8_lib implementation: snr = score * 0.5
/// We refine this with an offset to better match WSJT-X SNR values.
float compute_snr_db(const ftx_waterfall_t* wf,
                     const ftx_candidate_t* cand)
{
    // The candidate score comes from Costas sync correlation
    // Higher scores indicate stronger signals relative to noise
    // Typical scores range from 10 (minimum threshold) to ~50 (strong signal)
    
    // Linear approximation: SNR ≈ (score - 20) * 0.5
    // This maps score of 20 -> 0 dB, score of 10 -> -5 dB, score of 40 -> 10 dB
    // These values align reasonably well with typical FT8 SNR range of -24 to +10 dB
    
    float score = (float)cand->score;
    
    // Use a calibrated formula based on empirical observation
    // WSJT-X typically shows SNR in range -24 to +30 dB
    // Scores typically range from 10 (threshold) to 100+ (very strong)
    float snr_db = (score - 25.0f) * 0.5f;
    
    // Clamp to realistic FT8 SNR range
    if (snr_db < -24.0f) snr_db = -24.0f;
    if (snr_db > 30.0f) snr_db = 30.0f;
    
    return snr_db;
}


@end
