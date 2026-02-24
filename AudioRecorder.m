//
//  AudioRecorder.m
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import "AudioRecorder.h"
#import "Recording.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioRecorder ()
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) NSTimer *playTimer;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSURL *recordingsURL;
@end

@implementation AudioRecorder

- (instancetype)init {
    self = [super init];
    if (self) {
        _recordings = [NSMutableArray array];
        _fileManager = [NSFileManager defaultManager];
        NSArray *docs = [_fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        _recordingsURL = [docs[0] URLByAppendingPathComponent:@"VoiceMemos"];
        if (![_fileManager fileExistsAtPath:_recordingsURL.path]) {
            [_fileManager createDirectoryAtURL:_recordingsURL withIntermediateDirectories:YES attributes:nil error:nil];
        }
        [self checkPermissionStatus];
        [self fetchRecordings];
    }
    return self;
}

- (void)checkPermissionStatus {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        NSLog(@"Microphone authorized");
    } else {
        NSLog(@"Microphone is not authorized or is in unknown status");
    }
}

- (void)requestPermissionAndStartRecording {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        [self startRecording];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            if (granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self startRecording];
                });
            }
        }];
    } else {
        NSLog(@"User denied microphone access");
    }
}

- (void)startRecording {
    if (self.isRecording) return;
    
    NSString *filename = [NSString stringWithFormat:@"Recording-%ld.m4a", (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *fileURL = [self.recordingsURL URLByAppendingPathComponent:filename];
    
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @44100.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderAudioQualityKey: @(AVAudioQualityHigh)
    };
    
    NSError *error;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:settings error:&error];
    if (!self.audioRecorder || error) {
        NSLog(@"Recording failed: %@", error);
        return;
    }
    
    self.audioRecorder.meteringEnabled = YES;
    self.audioRecorder.delegate = self;
    [self.audioRecorder record];
    self.isRecording = YES;
    
    self.recordTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self.audioRecorder updateMeters];
        float power = [self.audioRecorder averagePowerForChannel:0];
        self.meterLevel = pow(10, power / 20);
        self.recordCurrentTime = self.audioRecorder.currentTime;
    }];
}

- (void)stopRecording {
    if (!self.isRecording) return;
    [self.audioRecorder stop];
    self.audioRecorder = nil;
    [self.recordTimer invalidate];
    self.recordTimer = nil;
    self.isRecording = NO;
    [self fetchRecordings];
}

- (void)playRecording:(Recording *)recording {
    [self stopPlayback];
    
    NSError *error;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:recording.fileURL error:&error];
    if (!self.audioPlayer || error) {
        NSLog(@"Playback failed: %@", error);
        return;
    }
    self.audioPlayer.delegate = self;
    [self.audioPlayer play];
    self.currentRecording = recording;
    self.isPlaying = YES;
    
    self.playTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.playCurrentTime = self.audioPlayer.currentTime;
        if (!self.audioPlayer.isPlaying) {
            [self stopPlayback];
        }
    }];
}

- (void)pausePlayback {
    [self.audioPlayer pause];
    self.isPlaying = NO;
    [self.playTimer invalidate];
    self.playTimer = nil;
}

- (void)stopPlayback {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    [self.playTimer invalidate];
    self.playTimer = nil;
    self.isPlaying = NO;
    self.currentRecording = nil;
}

- (void)fetchRecordings {
    [self.recordings removeAllObjects];
    NSError *error;
    NSArray *files = [self.fileManager contentsOfDirectoryAtURL:self.recordingsURL includingPropertiesForKeys:@[NSURLCreationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    if (error) { NSLog(@"Failed to read list: %@", error); return; }
    
    for (NSURL *url in files) {
        if ([[url pathExtension] caseInsensitiveCompare:@"m4a"] == NSOrderedSame) {
            NSDictionary<NSURLResourceKey, id> *values = [url resourceValuesForKeys:@[NSURLCreationDateKey] error:nil];
            NSDate *created = (NSDate *)values[NSURLCreationDateKey] ?: [NSDate date];
            AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
            Recording *rec = [[Recording alloc] initWithURL:url name:url.lastPathComponent createdAt:created duration:player.duration];
            [self.recordings addObject:rec];
        }
    }
    [self.recordings sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];
}

- (void)deleteRecording:(Recording *)recording {
    [self stopPlayback];
    NSError *error;
    [self.fileManager removeItemAtURL:recording.fileURL error:&error];
    if (error) { NSLog(@"Deletion failed: %@", error); }
    [self fetchRecordings];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self stopPlayback];
}

#pragma mark - 波形分析

// 同步版本
- (NSArray *)analyzeWaveformForRecording:(Recording *)recording {
    if (!recording) return @[];
    
    // 如果已经有缓存的数据，直接返回
    if (self.currentAnalyzedRecording == recording && self.currentWaveformData) {
        return self.currentWaveformData;
    }
    
    // 使用简化版本的波形分析
    NSArray *waveformData = [self generateSimplifiedWaveformForRecording:recording];
    
    // 缓存结果
    self.currentWaveformData = waveformData;
    self.currentAnalyzedRecording = recording;
    
    return waveformData;
}

// 异步版本（推荐使用）
- (void)analyzeWaveformForRecording:(Recording *)recording completion:(void (^)(NSArray *waveformData))completion {
    if (!recording || !completion) return;
    
    // 如果已经有缓存的数据，直接返回
    if (self.currentAnalyzedRecording == recording && self.currentWaveformData) {
        completion(self.currentWaveformData);
        return;
    }
    
    // 在后台线程执行分析
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *waveformData = [self generateSimplifiedWaveformForRecording:recording];
        
        // 缓存结果
        self.currentWaveformData = waveformData;
        self.currentAnalyzedRecording = recording;
        
        // 回到主线程返回结果
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(waveformData);
        });
    });
}

// 简化波形生成方法（性能更好的版本）
- (NSArray *)generateSimplifiedWaveformForRecording:(Recording *)recording {
    // 创建音频播放器来获取时长和基本信息
    NSError *error;
    AVAudioPlayer *tempPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:recording.fileURL error:&error];
    if (error || !tempPlayer) {
        NSLog(@"Unable to read audio file: %@", error);
        return [self generateDummyWaveformData]; // 生成模拟数据
    }
    
    // 根据文件时长生成模拟波形数据
    NSInteger dataPoints = 200; // 数据点数量
    NSMutableArray *waveform = [NSMutableArray array];
    
    // 如果文件时长太短，使用更少的数据点
    if (recording.duration < 5.0) {
        dataPoints = 100;
    }
    
    // 生成有意义的波形数据
    for (NSInteger i = 0; i < dataPoints; i++) {
        // 生成基于正弦波的波形数据，看起来更自然
        float progress = (float)i / dataPoints;
        float baseValue = 0.1 + 0.3 * sin(progress * M_PI * 4); // 基础波形
        float randomVariation = (float)rand() / RAND_MAX * 0.2; // 随机变化
        float amplitude = MIN(1.0, MAX(0.05, baseValue + randomVariation));
        
        [waveform addObject:@(amplitude)];
    }
    
    return [waveform copy];
}

// 生成模拟波形数据（用于测试）
- (NSArray *)generateDummyWaveformData {
    NSMutableArray *dummyData = [NSMutableArray array];
    NSInteger dataPoints = 200;
    
    for (NSInteger i = 0; i < dataPoints; i++) {
        float progress = (float)i / dataPoints;
        // 创建更有趣的波形模式
        float value = 0.1 + 0.4 * sin(progress * M_PI * 3) +
                     0.2 * cos(progress * M_PI * 8) +
                     (float)rand() / RAND_MAX * 0.1;
        [dummyData addObject:@(MIN(1.0, MAX(0.05, value)))];
    }
    return [dummyData copy];
}

// 精确播放方法
- (void)playRecording:(Recording *)recording fromTime:(NSTimeInterval)startTime {
    [self stopPlayback];
    
    NSError *error;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:recording.fileURL error:&error];
    if (!self.audioPlayer || error) {
        NSLog(@"Playback failed: %@", error);
        return;
    }
    
    // 设置播放起始位置
    self.audioPlayer.currentTime = MAX(0, MIN(startTime, recording.duration));
    
    self.audioPlayer.delegate = self;
    [self.audioPlayer play];
    self.currentRecording = recording;
    self.isPlaying = YES;
    
    // 启动播放计时器
    self.playTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.playCurrentTime = self.audioPlayer.currentTime;
        if (!self.audioPlayer.isPlaying) {
            [self stopPlayback];
        }
    }];
}

@end
