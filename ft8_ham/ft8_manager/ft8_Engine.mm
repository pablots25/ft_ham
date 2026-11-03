#import "ft8_Engine.h"
#import "ft8_SlotMonitor.h"

#include "decode.h"
#include "encode.h"
#include "monitor.h"
#include "text.h"

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

/// The protocol's 22-bit callsign hash, as defined for type-4 messages.
///
/// The library computes this while packing, but it keeps the routine private and
/// only records callsigns it has actually seen on the air. Seeding the table
/// with a callsign we already know needs the same number.
static uint32_t ft8_callsign_hash22(const char *callsign) {
  uint64_t n58 = 0;
  int i = 0;
  for (; callsign[i] != '\0' && i < 11; ++i) {
    int j = nchar(callsign[i], FT8_CHAR_TABLE_ALPHANUM_SPACE_SLASH);
    if (j < 0) return UINT32_MAX; // character a callsign cannot contain
    n58 = (38 * n58) + j;
  }
  for (; i < 11; ++i) {
    n58 = 38 * n58; // pad with trailing spaces (index 0)
  }
  return (uint32_t)((47055833459ull * n58) >> (64 - 22)) & 0x3FFFFFu;
}

/// Teaches the decoder a callsign it has not heard spelled out on the air.
///
/// A station answering us with a compound callsign of their own sends *our*
/// callsign as a 12-bit hash. Without this the reply decodes as "<...> THEIRCALL"
/// and never reads as addressed to us. Called from the decode thread only, which
/// is the only thread that touches the table.
static void ft8_register_known_callsign(NSString *callsign) {
  if (callsign.length == 0 || callsign.length > 11) return;
  const char *c = [callsign UTF8String];
  if (c == NULL) return;
  uint32_t hash = ft8_callsign_hash22(c);
  if (hash == UINT32_MAX) return;
  hashtable_add(c, hash);
}

// -----------------------------------------------------------------------------
// MARK: - Compound Callsign Encoding
// -----------------------------------------------------------------------------
// A compound callsign such as "I/VE6XAD" does not fit the standard 28-bit
// callsign field. The protocol carries it in a type-4 message instead, where one
// call is spelled out in full and the other is sent as a 12-bit hash.
//
// ftx_message_encode() only falls back to that type when the standard packer
// fails outright. For a prefixed call the standard packer "succeeds" by
// replacing the call with a 22-bit hash, so a CQ would go on the air as "CQ
// <...>" for every receiver that has never heard the call spelled out. Deciding
// here which messages need a type-4 keeps the compound call readable on the air.

/// True when `call` fits the standard callsign field: a plain call, a protocol
/// token, or a call carrying the protocol's own /P and /R suffixes.
static BOOL ft8_callsign_is_standard(const char *call) {
  if (call == NULL) return YES;
  size_t len = strlen(call);
  if (len == 0) return YES; // absent field (e.g. call_to of a CQ)

  if (strcmp(call, "CQ") == 0 || strcmp(call, "DE") == 0 ||
      strcmp(call, "QRZ") == 0 || strncmp(call, "CQ ", 3) == 0) {
    return YES;
  }

  size_t base_len = len;
  if (len > 2 && (strcmp(call + len - 2, "/P") == 0 ||
                  strcmp(call + len - 2, "/R") == 0)) {
    base_len = len - 2;
  }

  return pack_basecall(call, (int)base_len) >= 0;
}

/// True when a type-4 message can carry this exchange.
///
/// Besides the two callsigns it has room for one of RRR/RR73/73, and nothing
/// else. A grid or a signal report has to travel in a standard message, where
/// the compound call is replaced by a hash the other station resolves from the
/// CQ it already decoded — which is what WSJT-X does too.
///
/// A CQ is the exception: it is the message that teaches everyone the call, so
/// it is always worth sending as type 4 even though the grid cannot come along.
static BOOL ft8_fits_nonstandard(const char *extra, BOOL isCQ) {
  if (isCQ) return YES;
  if (extra == NULL || extra[0] == '\0') return YES;
  return strcmp(extra, "RRR") == 0 || strcmp(extra, "RR73") == 0 ||
         strcmp(extra, "73") == 0;
}

// -----------------------------------------------------------------------------
// MARK: - Protocol Parameters
// -----------------------------------------------------------------------------
// Every protocol-dependent constant lives here so new modes only need a new
// case in each helper.

// ftx_protocol_for_mode() is shared with the slot monitor (ft8_EngineProtocol.h).

/// FT4 and FT2 share the 4-GFSK frame (105 symbols, ft4_encode, BT 1.0).
static BOOL is_4fsk_mode(FTXEngineProtocol mode) {
  return ftx_protocol_for_mode(mode) == FTX_PROTOCOL_FT4;
}

static float symbol_period_for_mode(FTXEngineProtocol mode) {
  switch (mode) {
  case FTXEngineProtocolFT4:
    return FT4_SYMBOL_PERIOD;
  case FTXEngineProtocolFT2:
    return FT2_SYMBOL_PERIOD;
  case FTXEngineProtocolFT8:
  default:
    return FT8_SYMBOL_PERIOD;
  }
}

static float slot_time_for_mode(FTXEngineProtocol mode) {
  switch (mode) {
  case FTXEngineProtocolFT4:
    return FT4_SLOT_TIME;
  case FTXEngineProtocolFT2:
    return FT2_SLOT_TIME;
  case FTXEngineProtocolFT8:
  default:
    return FT8_SLOT_TIME;
  }
}

static int num_tones_for_mode(FTXEngineProtocol mode) {
  return is_4fsk_mode(mode) ? FT4_NN : FT8_NN;
}

static float symbol_bt_for_mode(FTXEngineProtocol mode) {
  return is_4fsk_mode(mode) ? 1.0f : 2.0f;
}

/// Physical signal length (s) used to flag partial slots.
static double signal_duration_for_mode(FTXEngineProtocol mode) {
  switch (mode) {
  case FTXEngineProtocolFT4:
    return 4.5;
  case FTXEngineProtocolFT2:
    return 2.52; // 105 symbols x 24 ms
  case FTXEngineProtocolFT8:
  default:
    return 12.6;
  }
}

/// Safety margin (s) added to the signal length for partial slot detection.
static double decode_margin_for_mode(FTXEngineProtocol mode) {
  return is_4fsk_mode(mode) ? 0.1 : 0.2;
}

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

- (NSArray<NSDictionary *> *)decode:(nullable NSURL *)input
                               mode:(FTXEngineProtocol)mode {
#if TARGET_OS_SIMULATOR
  if (input) {
    NSLog(@"[FT8] Decoding WAV (Simulator)");
    return [self decodeFromWAV:input mode:mode];
  } else {
    NSLog(@"[FT8] Simulator without input file: microphone not available.");
    return @[];
  }
#else
  if (input) {
    NSLog(@"[FT8] Decoding WAV (Device)");
    return [self decodeFromWAV:input mode:mode];
  } else {
    NSLog(@"[FT8] Decoding in real-time from microphone");
    return [self decodeFromMic:mode];
  }
#endif
}

#pragma mark - Decoding from WAV File

- (NSArray<NSDictionary *> *)decodeFromWAV:(NSURL *)wavURL
                                      mode:(FTXEngineProtocol)mode {
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
                                   mode:mode];
}

#pragma mark - Real-time Decoding from Microphone

- (NSArray<NSDictionary *> *)decodeFromMic:(FTXEngineProtocol)mode {
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
                                                 mode:mode];
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

// NOTE: startRealtimeDecode:messageHandler: is legacy code that is never called
// from Swift. AVAudioSession ownership and all audio I/O were migrated to
// AudioManager.swift. The AVAudioSession configuration below is therefore dead
// code and does not conflict with the live session at runtime.
- (void)startRealtimeDecode:(FTXEngineProtocol)mode
             messageHandler:
                 (void (^)(NSArray<NSDictionary *> *messages))handler {
  if (self.isCapturing)
    return;
  self.isCapturing = YES;

  // AVAudioSession setup
  NSError *sessionError = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [session setCategory:AVAudioSessionCategoryPlayAndRecord
           withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                       AVAudioSessionCategoryOptionAllowBluetooth |
                       AVAudioSessionCategoryOptionAllowBluetoothA2DP
                 error:&sessionError];
#pragma clang diagnostic pop
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

  double slotTime = slot_time_for_mode(mode);

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
                                                          mode:mode];

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
                                                 mode:(FTXEngineProtocol)mode {
  // Second-line defence: reject invalid sample rates before they reach monitor_init,
  // where sample_rate=0 would produce nfft=0 and crash KISS FFT.
  if (sampleRate <= 0) {
    [self logFT8:@"decodeBufferUsingMonitor: invalid sampleRate=%.1f – aborting to prevent FFT crash", sampleRate];
    return @[];
  }
  const float *audio = (const float *)audioData.bytes;
  NSUInteger nSamples = audioData.length / sizeof(float);
  ftx_protocol_t protocol = ftx_protocol_for_mode(mode);

  monitor_t mon;
  monitor_config_t cfg = {.f_min = 200,
                          .f_max = 3000,
                          .sample_rate = (int)sampleRate,
                          .time_osr = 2,
                          .freq_osr = 2,
                          .protocol = protocol};

  ftx_monitor_init_for_mode(&mon, &cfg, mode);

  int blockSize = mon.block_size;
  for (int pos = 0; pos + blockSize <= nSamples; pos += blockSize) {
    monitor_process(&mon, audio + pos);
  }

  NSArray<NSDictionary *> *results =
      [self decodeWaterfall:&mon.wf
                     minBin:mon.min_bin
               symbolPeriod:mon.symbol_period
                       mode:mode
             coveredSeconds:(double)nSamples / sampleRate];

  monitor_free(&mon);
  return results;
}

- (NSArray<NSDictionary *> *)decodeSlotSnapshot:(FT8WaterfallSnapshot *)snapshot
                                                 mode:(FTXEngineProtocol)mode {
  return [self decodeWaterfall:snapshot.waterfall
                        minBin:snapshot.minBin
                  symbolPeriod:snapshot.symbolPeriod
                          mode:mode
                coveredSeconds:snapshot.duration];
}

/// Shared decode core: candidate search, LDPC decode and message unpacking
/// over an already-analysed spectrogram, whether it came from a one-off
/// batch monitor (WAV files, buffers) or from the streaming slot monitor.
/// `coveredSeconds` is how much audio the spectrogram spans; it decides
/// whether an empty result is reported as a partial slot.
- (NSArray<NSDictionary *> *)decodeWaterfall:(const ftx_waterfall_t *)wf
                                      minBin:(int)minBin
                                symbolPeriod:(float)symbolPeriod
                                        mode:(FTXEngineProtocol)mode
                              coveredSeconds:(double)coveredSeconds {
  // The callsign hash table has to live across slots: a compound callsign is
  // spelled out once and referred to by hash afterwards, often slots later.
  // Re-initialising it per buffer would erase every call learned so far and
  // leave those messages decoding as "<...>". Ageing is handled by
  // hashtable_cleanup() at the end of each pass instead.
  static dispatch_once_t hashtableOnce;
  dispatch_once(&hashtableOnce, ^{
    hashtable_init();
  });

  // Our own callsign is never learned from the air, so seed it every pass: a
  // station answering us with a compound callsign refers to us by hash, and
  // ageing can retire the entry between overs.
  ft8_register_known_callsign([[[NSUserDefaults standardUserDefaults]
      stringForKey:@"callsign"] uppercaseString]);

  // ------------------------------------------------------------
  // Find candidates
  // ------------------------------------------------------------
  ftx_candidate_t candidates[140];
  int nCand = ftx_find_candidates_for_mode(wf, 140, candidates, 10, mode);

  NSMutableArray<NSDictionary *> *results = [NSMutableArray array];

  for (int i = 0; i < nCand; i++) {
    ftx_message_t msg;
    ftx_decode_status_t status;
    if (ftx_decode_candidate(wf, &candidates[i], 25, &msg, &status)) {
      char text[FTX_MAX_MESSAGE_LENGTH];
      ftx_message_offsets_t offsets;
      ftx_message_rc_t rc = ftx_message_decode(&msg, &hash_if, text, &offsets);

      // stringWithUTF8String: returns nil on bytes that are not valid UTF-8;
      // a nil text would crash both the literal below and the dedup map.
      NSString *messageText =
          rc == FTX_MESSAGE_RC_OK ? [NSString stringWithUTF8String:text] : nil;
      if (messageText != nil) {
        float snr = compute_snr_db(wf, &candidates[i]);

        float timeSec = (candidates[i].time_offset +
                         (float)candidates[i].time_sub / wf->time_osr) *
                        symbolPeriod;
        float freqHz = (minBin + candidates[i].freq_offset +
                        (float)candidates[i].freq_sub / wf->freq_osr) /
                       symbolPeriod;

        NSDate *now = [NSDate date]; // current date and time
        NSTimeInterval timestamp =
            [now timeIntervalSince1970]; // seconds since 1970

        NSDictionary *msgDict = @{
          @"text" : messageText,
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

  hashtable_cleanup(10);

  NSMutableDictionary<NSString *, NSDictionary *> *bestResults =
      [NSMutableDictionary dictionary];
  for (NSDictionary *msg in results) {
    NSString *text = msg[@"text"];
    if (text == nil) {
      continue;
    }
    double snr = [msg[@"snr"] doubleValue];

    NSDictionary *existing = bestResults[text];
    if (!existing || snr > [existing[@"snr"] doubleValue]) {
      bestResults[text] = msg;
    }
  }

    // Check for partial signal
    double signalDuration = signal_duration_for_mode(mode); // physical signal length
    double decodeMargin   = decode_margin_for_mode(mode);   // safety margin

    // Only report partial slot if we could not decode any valid messages
    if (coveredSeconds < signalDuration + decodeMargin && bestResults.count == 0) {
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

#pragma mark - Message Encoding

/// Packs `message` into an FT8/FT4 payload, choosing the message type that keeps
/// a compound callsign readable on the air.
///
/// Everything else is handed straight to the library. Both callsigns are
/// registered in the local hash table on the way out, so a reply that refers to
/// them by hash is displayed with the call spelled out.
- (ftx_message_rc_t)encodeMessage:(NSString *)message
                             into:(ftx_message_t *)outMessage {
  const char *raw = [message UTF8String];
  if (raw == NULL) {
    return FTX_MESSAGE_RC_ERROR_TYPE;
  }

  NSArray<NSString *> *tokens = [[message
      componentsSeparatedByCharactersInSet:[NSCharacterSet
                                               whitespaceCharacterSet]]
      filteredArrayUsingPredicate:[NSPredicate
                                      predicateWithFormat:@"length > 0"]];

  if (tokens.count >= 2) {
    BOOL isCQ = [tokens[0] isEqualToString:@"CQ"];
    NSString *callTo = @"";
    NSString *callDe = @"";
    NSString *extra = @"";

    if (isCQ) {
      // "CQ DX EA4IQL IN80" keeps the modifier with the CQ token; a three-token
      // CQ whose middle token is a callsign is "CQ <call> <grid>" instead.
      BOOL hasModifier =
          tokens.count >= 3 && tokens[1].length <= 4 &&
          [tokens[1] rangeOfString:@"/"].location == NSNotFound &&
          !ft8_callsign_is_standard([tokens[1] UTF8String]);
      if (hasModifier) {
        callTo = [NSString stringWithFormat:@"CQ %@", tokens[1]];
        callDe = tokens[2];
        extra = tokens.count >= 4 ? tokens[3] : @"";
      } else {
        callTo = @"CQ";
        callDe = tokens[1];
        extra = tokens.count >= 3 ? tokens[2] : @"";
      }
    } else {
      callTo = tokens[0];
      callDe = tokens[1];
      extra = tokens.count >= 3 ? tokens[2] : @"";
    }

    const char *cTo = [callTo UTF8String];
    const char *cDe = [callDe UTF8String];
    const char *cExtra = [extra UTF8String];

    BOOL compound =
        !ft8_callsign_is_standard(cTo) || !ft8_callsign_is_standard(cDe);

    if (compound && ft8_fits_nonstandard(cExtra, isCQ)) {
      if (isCQ && cExtra != NULL && cExtra[0] != '\0') {
        [self logFT8:@"Compound callsign CQ: '%@' cannot be sent with a grid, "
                     @"transmitting '%@ %@'",
                     message, callTo, callDe];
      }
      // hash_if is left out on purpose: the table belongs to the decode path
      // and is read from the audio queue. The packers do not need it to build
      // the message, only to record what they packed.
      ftx_message_rc_t rc =
          ftx_message_encode_nonstd(outMessage, NULL, cTo, cDe, cExtra);
      if (rc == FTX_MESSAGE_RC_OK) {
        return rc;
      }
      [self logFT8:@"Non-standard encoding failed for '%@' (%d), falling back",
                   message, rc];
    }
  }

  return ftx_message_encode(outMessage, NULL, raw);
}

#pragma mark - FT8/FT4 Signal Generation

- (NSData *)generateFT8:(NSString *)message
              frequency:(float)frequency
                   mode:(FTXEngineProtocol)mode
                 toFile:(nullable NSURL *)outputURL {
  // Encode message
  ftx_message_t ftxMsg;
  ftx_message_rc_t rc = [self encodeMessage:message into:&ftxMsg];
  if (rc != FTX_MESSAGE_RC_OK) {
    [self logFT8:@"Error packing message (%d)", rc];
    return nil;
  }

  return [self audioForPayload:&ftxMsg
                     frequency:frequency
                          mode:mode
                        toFile:outputURL];
}

/// Free text bypasses `encodeMessage:` on purpose: that path hands any 2+
/// token string to the standard/non-standard packers first, which would turn
/// "HELLO WORLD" into a hashed callsign pair instead of a type-0.0 message.
- (nullable NSData *)generateFreeText:(NSString *)text
                            frequency:(float)frequency
                                 mode:(FTXEngineProtocol)mode {
  const char *raw = [text UTF8String];
  if (raw == NULL) {
    return nil;
  }
  ftx_message_t ftxMsg;
  ftx_message_rc_t rc = ftx_message_encode_free(&ftxMsg, raw);
  if (rc != FTX_MESSAGE_RC_OK) {
    [self logFT8:@"Error packing free text '%@' (%d)", text, rc];
    return nil;
  }
  return [self audioForPayload:&ftxMsg frequency:frequency mode:mode toFile:nil];
}

/// GFSK synthesis shared by every encoder entry point.
- (nullable NSData *)audioForPayload:(const ftx_message_t *)ftxMsgPtr
                           frequency:(float)frequency
                                mode:(FTXEngineProtocol)mode
                              toFile:(nullable NSURL *)outputURL {
  const ftx_message_t ftxMsg = *ftxMsgPtr;
  int numTones = num_tones_for_mode(mode);
  float symbolPeriod = symbol_period_for_mode(mode);
  float symbolBT = symbol_bt_for_mode(mode);
  float slotTime = slot_time_for_mode(mode);
  int sampleRate = 12000;

  uint8_t tones[numTones];
  if (is_4fsk_mode(mode)) {
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
