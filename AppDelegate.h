//
//  AppDelegate.h
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import <Cocoa/Cocoa.h>
#import "AudioRecorder.h"
#import <Speech/Speech.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (strong, nonatomic) AudioRecorder *audioRecorder;
@property (strong) NSTableView *tableView;
@property (strong) NSProgressIndicator *meterProgress;

// 在现有属性后添加
@property (strong) NSPopUpButton *languagePopup;
@property (strong) NSDictionary *supportedLanguages;
@property (strong) NSString *currentTargetLanguage;

// 在方法声明中添加
- (void)translateRecordingText:(NSString *)text targetLanguage:(NSString *)targetLang;
- (void)setupLanguagePopup;
- (void)languagePopupChanged:(id)sender;

// 播放控制按钮
@property (strong) NSButton *playButton;
@property (strong) NSButton *pauseButton;
@property (strong) NSButton *stopPlaybackButton;

// 波形显示相关
@property (strong) NSView *waveformView;
@property (strong) NSProgressIndicator *playbackPositionIndicator;
@property (assign) BOOL isDraggingPlayhead;
@property (assign) CGFloat playheadPosition; // 0.0 - 1.0

@end
