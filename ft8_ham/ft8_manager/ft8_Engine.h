//
//  ft8_engine.h
//  ft_ham
//
//  Created by Pablo Turrion on 18/10/25.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- C demo headers ---
#include <common/common.h>
#include <common/monitor.h>
#include <common/wave.h>
#include <ft8/decode.h>
#include <ft8/encode.h>
#include <ft8/message.h>

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_BEGIN

@interface ft8_Engine : NSObject

#pragma mark - Encoding

/// Generates FT8 or FT4 audio for the specified message.
/// Can optionally save the audio as a WAV file.
/// @param message The message to encode (e.g., "CQ DX").
/// @param frequency The transmit frequency in Hz (float).
/// @param isFT4 YES to generate FT4 audio, NO for FT8.
/// @param outputURL Optional file URL to write WAV. Pass nil to skip saving.
/// @return Float32 PCM audio data (12 kHz, mono), or nil if failed.
- (nullable NSData *)generateFT8:(NSString *)message
                       frequency:(float)frequency
                           isFT4:(BOOL)isFT4
                          toFile:(nullable NSURL *)outputURL;

/// Synthesizes GFSK signal from symbols (internal helper)
/// @param symbols Array of tone symbols.
/// @param n_sym Number of symbols.
/// @param f0 Center frequency in Hz.
/// @param symbol_bt Gaussian BT factor.
/// @param symbol_period Symbol duration in seconds.
/// @param sampleRate Output sample rate (Hz).
/// @param output Output float32 buffer (preallocated).
- (void)synthGFSK:(const uint8_t *)symbols
             nSym:(int)n_sym
               f0:(float)f0
         symbolBT:(float)symbol_bt
     symbolPeriod:(float)symbol_period
       sampleRate:(int)sampleRate
           output:(float *)output;

#pragma mark - Real-Time Decoding

/// Starts real-time decoding from the device microphone.
/// Calls the handler with all decoded messages each slot (~15 s FT8, ~7.5 s
/// FT4).
/// @param isFT4 YES for FT4 decoding, NO for FT8.
/// @param handler Block called with decoded message dictionaries.
- (void)startRealtimeDecode:(BOOL)isFT4
             messageHandler:
                 (void (^_Nonnull)(NSArray<NSDictionary *> *_Nonnull messages))
                     handler;

/// Stops real-time decoding and releases audio resources.
- (void)stopRealtimeDecode;

#pragma mark - File / Buffer Decoding

/// Decodes FT8 or FT4 from an audio file URL.
/// @param input File URL to decode, can be nil.
/// @param isFT4 YES for FT4 decoding, NO for FT8.
/// @return Array of decoded messages as strings.
- (NSArray<NSDictionary *> *)decode:(nullable NSURL *)input isFT4:(BOOL)isFT4;

- (NSArray<NSDictionary *> *)decodeFromWAV:(NSURL *)wavURL isFT4:(BOOL)isFT4;

- (NSArray<NSDictionary *> *)decodeBufferUsingMonitor:(NSData *)audioData
                                           sampleRate:(double)sampleRate
                                                isFT4:(BOOL)isFT4;

@end

NS_ASSUME_NONNULL_END
