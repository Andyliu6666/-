//
//  AudioRecorder.h
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "Recording.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioRecorder : NSObject <AVAudioRecorderDelegate, AVAudioPlayerDelegate>

@property (nonatomic, strong) NSMutableArray<Recording *> *recordings;
@property (nonatomic, strong, nullable) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic) BOOL isRecording;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) NSTimeInterval recordCurrentTime;
@property (nonatomic) NSTimeInterval playCurrentTime;
@property (nonatomic) float meterLevel;
@property (nonatomic, strong, nullable) Recording *currentRecording;

// 波形分析相关属性
@property (nonatomic, strong, nullable) NSArray *currentWaveformData;
@property (nonatomic, strong, nullable) Recording *currentAnalyzedRecording;

- (void)checkPermissionStatus;
- (void)requestPermissionAndStartRecording;
- (void)startRecording;
- (void)stopRecording;
- (void)playRecording:(Recording *)recording;
- (void)pausePlayback;
- (void)stopPlayback;
- (void)fetchRecordings;  // 注意：这里应该是fetchRecordings（复数），不是fetchRecording
- (void)deleteRecording:(Recording *)recording;

// 波形分析和精确播放方法
- (NSArray *)analyzeWaveformForRecording:(Recording *)recording;
- (void)playRecording:(Recording *)recording fromTime:(NSTimeInterval)startTime;

// 简化波形分析方法
- (void)analyzeWaveformForRecording:(Recording *)recording completion:(void (^)(NSArray *waveformData))completion;

@end

NS_ASSUME_NONNULL_END
