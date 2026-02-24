//
//  AppDelegate.m
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import "AppDelegate.h"
#import "AudioRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

@interface AppDelegate () <NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate>

@property (strong) NSSearchField *searchField;
@property (strong) NSButton *renameButton;
@property (strong) NSButton *transcribeButton;
@property (strong) NSButton *translateButton;
@property (strong) NSButton *deleteButton;
@property (strong) NSTextView *transcriptionTextView;
@property (strong) NSTextView *translationTextView;
@property (strong) NSScrollView *transcriptionScrollView;
@property (strong) NSScrollView *translationScrollView;
@property (strong) NSArray<Recording *> *filteredRecordings;

// Speech框架相关
@property (strong) SFSpeechRecognizer *speechRecognizer;
@property (strong) SFSpeechRecognitionTask *recognitionTask;
@property (assign) BOOL isTranscribing;
@property (strong) NSProgressIndicator *transcriptionProgress;

// 波形数据
@property (strong) NSArray *waveformData; // 存储波形数据点
@property (strong) NSButton *playFromCursorButton;

@property (strong) NSTimer *statusUpdateTimer;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.audioRecorder = [[AudioRecorder alloc] init];
    
    // 初始化语音识别
    [self setupSpeechRecognizer];
    
    // 创建窗口
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,850,700)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
                                                       NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    [self.window center];
    [self.window setTitle:@"Recording Notes"];
    [self.window setMinSize:NSMakeSize(700, 600)];
    [self.window makeKeyAndOrderFront:nil];
    
    // 设置UI
    [self setupModernUI];
    [self.audioRecorder fetchRecordings];
    self.filteredRecordings = self.audioRecorder.recordings;
}

- (void)setupSpeechRecognizer {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (status) {
                case SFSpeechRecognizerAuthorizationStatusAuthorized:
                    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"zh-CN"]];
                    self.speechRecognizer.defaultTaskHint = SFSpeechRecognitionTaskHintDictation;
                    NSLog(@"Voice recognition permission has been authorized");
                    break;
                default:
                    NSLog(@"Limited voice recognition permissions");
                    break;
            }
        });
    }];
}

- (void)setupModernUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    
    // 搜索框 - 顶部
        self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 660, 650, 28)]; // 减小宽度为语言选择器留空间
        self.searchField.placeholderString = @"Search for recording files...";
        self.searchField.delegate = self;
        [contentView addSubview:self.searchField];
    
    // 语言选择器 - 在搜索框旁边
        self.languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(680, 660, 150, 28)];
        [self setupLanguagePopup];
        [contentView addSubview:self.languagePopup];
    
    // 功能按钮区域
    NSStackView *functionStack = [[NSStackView alloc] initWithFrame:NSMakeRect(20, 620, 810, 32)];
    functionStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    functionStack.spacing = 10;
    functionStack.distribution = NSStackViewDistributionFillEqually;
    
    NSArray *buttonTitles = @[@"rename", @"transfer to text", @"translate", @"delete"];
    NSArray *buttonActions = @[
        NSStringFromSelector(@selector(renameClicked:)),
        NSStringFromSelector(@selector(transcribeClicked:)),
        NSStringFromSelector(@selector(translateClicked:)),
        NSStringFromSelector(@selector(deleteClicked:))
    ];
    
    for (NSInteger i = 0; i < buttonTitles.count; i++) {
        NSButton *button = [NSButton buttonWithTitle:buttonTitles[i] target:self action:NSSelectorFromString(buttonActions[i])];
        button.enabled = NO;
        button.bezelStyle = NSBezelStyleRounded;
        
        if (i == 4) {
            button.keyEquivalent = @"\b";
            button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        }
        
        [functionStack addArrangedSubview:button];
        
        switch (i) {
            case 0: self.renameButton = button; break;
            case 1: self.transcribeButton = button; break;
            case 2: self.translateButton = button; break;
            case 3: self.deleteButton = button; break;
        }
    }
    
    [contentView addSubview:functionStack];
    
    // 波形显示区域 - 在功能按钮下方
    [self setupWaveformAreaInView:contentView];
    
    // 录音控制区域 - 在波形显示下方
    NSView *recordControlView = [[NSView alloc] initWithFrame:NSMakeRect(20, 470, 810, 40)];
    
    // 权限按钮
    NSButton *micBtn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 5, 100, 30)];
    [micBtn setTitle:@"Permissions"];
    [micBtn setTarget:self];
    [micBtn setAction:@selector(micPermissionClicked:)];
    micBtn.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:micBtn];
    
    // 录音按钮
    NSButton *recordBtn = [[NSButton alloc] initWithFrame:NSMakeRect(110, 5, 80, 30)];
    [recordBtn setTitle:@"Start"];
    [recordBtn setTarget:self];
    [recordBtn setAction:@selector(startRecordingClicked:)];
    recordBtn.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:recordBtn];
    
    NSButton *stopBtn = [[NSButton alloc] initWithFrame:NSMakeRect(200, 5, 80, 30)];
    [stopBtn setTitle:@"Stop"];
    [stopBtn setTarget:self];
    [stopBtn setAction:@selector(stopRecordingClicked:)];
    stopBtn.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:stopBtn];
    
    // 播放控制按钮
    self.playButton = [[NSButton alloc] initWithFrame:NSMakeRect(290, 5, 60, 30)];
    [self.playButton setTitle:@"Play"];
    [self.playButton setTarget:self];
    [self.playButton setAction:@selector(playClicked:)];
    [self.playButton setEnabled:NO];
    self.playButton.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:self.playButton];
    
    self.pauseButton = [[NSButton alloc] initWithFrame:NSMakeRect(360, 5, 60, 30)];
    [self.pauseButton setTitle:@"Pause"];
    [self.pauseButton setTarget:self];
    [self.pauseButton setAction:@selector(pauseClicked:)];
    [self.pauseButton setEnabled:NO];
    self.pauseButton.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:self.pauseButton];
    
    self.stopPlaybackButton = [[NSButton alloc] initWithFrame:NSMakeRect(430, 5, 60, 30)];
    [self.stopPlaybackButton setTitle:@"Stop"];
    [self.stopPlaybackButton setTarget:self];
    [self.stopPlaybackButton setAction:@selector(stopPlaybackClicked:)];
    [self.stopPlaybackButton setEnabled:NO];
    self.stopPlaybackButton.bezelStyle = NSBezelStyleRounded;
    [recordControlView addSubview:self.stopPlaybackButton];
    
    // 音量指示器
    self.meterProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(500, 10, 200, 20)];
    self.meterProgress.minValue = 0;
    self.meterProgress.maxValue = 1;
    [self.meterProgress setStyle:NSProgressIndicatorStyleBar];
    [recordControlView addSubview:self.meterProgress];
    
    // 录音状态标签
    NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(710, 5, 100, 30)];
    statusLabel.stringValue = @"Ready";
    statusLabel.editable = NO;
    statusLabel.bezeled = NO;
    statusLabel.drawsBackground = NO;
    statusLabel.textColor = [NSColor secondaryLabelColor];
    statusLabel.tag = 100; // 用于后续更新
    [recordControlView addSubview:statusLabel];
    
    [contentView addSubview:recordControlView];
    
    // 录音列表表格 - 在录音控制下方
    self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(20, 220, 810, 240)];
    
    // 多列表格
    NSArray *columns = @[
        @[@"Recording files", @"NameColumn", @400],
        @[@"Creation time", @"DateColumn", @200],
        @[@"Duration", @"DurationColumn", @100],
        @[@"Size", @"SizeColumn", @110]
    ];
    
    for (NSArray *colInfo in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:colInfo[1]];
        [column.headerCell setStringValue:colInfo[0]];
        column.width = [colInfo[2] floatValue];
        [self.tableView addTableColumn:column];
    }
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.doubleAction = @selector(tableViewDoubleClick:);
    self.tableView.allowsMultipleSelection = NO;
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 220, 810, 240)];
    [scrollView setDocumentView:self.tableView];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [contentView addSubview:scrollView];
    
    // 转文本区域 - 在表格下方
    [self setupTextAreasInView:contentView];
    
    // 进度指示器
    self.transcriptionProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(400, 185, 100, 20)];
    self.transcriptionProgress.style = NSProgressIndicatorStyleSpinning;
    self.transcriptionProgress.hidden = YES;
    [contentView addSubview:self.transcriptionProgress];
    
    // 状态更新计时器
    self.statusUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self updateUIStatus];
    }];
}

- (void)setupTextAreasInView:(NSView *)contentView {
    // 转文本区域
    NSTextField *transcriptionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 190, 400, 20)];
    transcriptionLabel.stringValue = @"Translated text results:";
    transcriptionLabel.editable = NO;
    transcriptionLabel.bezeled = NO;
    transcriptionLabel.drawsBackground = NO;
    transcriptionLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [contentView addSubview:transcriptionLabel];
    
    self.transcriptionTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(20, 50, 400, 130)];
    self.transcriptionTextView.editable = YES;
    self.transcriptionTextView.font = [NSFont systemFontOfSize:12];
    self.transcriptionTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    self.transcriptionScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 50, 400, 130)];
    [self.transcriptionScrollView setDocumentView:self.transcriptionTextView];
    [self.transcriptionScrollView setHasVerticalScroller:YES];
    [self.transcriptionScrollView setBorderType:NSBezelBorder];
    [contentView addSubview:self.transcriptionScrollView];
    
    // 翻译区域
    NSTextField *translationLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(430, 190, 400, 20)];
    translationLabel.stringValue = @"Translation results:";
    translationLabel.editable = NO;
    translationLabel.bezeled = NO;
    translationLabel.drawsBackground = NO;
    translationLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [contentView addSubview:translationLabel];
    
    self.translationTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(430, 50, 400, 130)];
    self.translationTextView.editable = YES;
    self.translationTextView.font = [NSFont systemFontOfSize:12];
    self.translationTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    self.translationScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(430, 50, 400, 130)];
    [self.translationScrollView setDocumentView:self.translationTextView];
    [self.translationScrollView setHasVerticalScroller:YES];
    [self.translationScrollView setBorderType:NSBezelBorder];
    [contentView addSubview:self.translationScrollView];
    
    // 底部状态栏
    NSTextField *footerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 810, 20)];
    footerLabel.stringValue = @"Tip: Double-click the recording file to play it quickly | ⌘+Delete delete the file | Support Chinese speech recognition";
    footerLabel.editable = NO;
    footerLabel.bezeled = NO;
    footerLabel.drawsBackground = NO;
    footerLabel.textColor = [NSColor tertiaryLabelColor];
    footerLabel.font = [NSFont systemFontOfSize:11];
    [contentView addSubview:footerLabel];
}

#pragma mark - UI状态更新
- (void)updateUIStatus {
    // 更新音量指示器
    self.meterProgress.doubleValue = self.audioRecorder.meterLevel;
    
    // 更新按钮状态
    BOOL hasSelection = self.tableView.selectedRow >= 0;
    NSArray *functionButtons = @[self.renameButton, self.transcribeButton,
                                self.translateButton, self.deleteButton];
    
    for (NSButton *button in functionButtons) {
        button.enabled = hasSelection;
    }
    
    // 更新播放按钮状态
    self.playButton.enabled = hasSelection && !self.audioRecorder.isPlaying;
    self.pauseButton.enabled = self.audioRecorder.isPlaying;
    self.stopPlaybackButton.enabled = self.audioRecorder.isPlaying;
    
    // 更新转文本按钮状态
    if (self.isTranscribing) {
        self.transcribeButton.title = @"Stop text conversion";
        self.transcribeButton.enabled = YES;
    } else {
        self.transcribeButton.title = @"Convert text";
        self.transcribeButton.enabled = hasSelection;
    }
    
    // 更新状态标签
    NSTextField *statusLabel = [self.window.contentView viewWithTag:100];
    if (!statusLabel) { return; }
    if (self.audioRecorder.isRecording) {
        statusLabel.stringValue = @"Recording...";
        statusLabel.textColor = [NSColor systemRedColor];
    } else if (self.audioRecorder.isPlaying) {
        statusLabel.stringValue = @"Playing...";
        statusLabel.textColor = [NSColor systemGreenColor];
    } else {
        statusLabel.stringValue = @"Ready";
        statusLabel.textColor = [NSColor secondaryLabelColor];
    }
    
    // 更新波形显示
        static NSInteger lastSelectedRow = -1;
        if (self.tableView.selectedRow != lastSelectedRow) {
            lastSelectedRow = self.tableView.selectedRow;
            [self updateWaveformForSelectedRecording];
        }
        
    // 更新播放指针位置（如果正在播放）
        if (self.audioRecorder.isPlaying && self.audioRecorder.currentRecording) {
            Recording *currentRecording = self.audioRecorder.currentRecording;
            if (currentRecording.duration > 0) {
                self.playheadPosition = self.audioRecorder.playCurrentTime / currentRecording.duration;
                [self drawPlayhead];
            }
        }
}

#pragma mark - 新增功能方法
- (void)deleteClicked:(id)sender {
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[selectedRow];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Confirm Delete";
        alert.informativeText = [NSString stringWithFormat:@"Are you sure you want to delete \"%@\"? This action cannot be undone",
                                [recording.name stringByDeletingPathExtension]];
        [alert addButtonWithTitle:@"delete"];
        [alert addButtonWithTitle:@"cancel"];
        alert.alertStyle = NSAlertStyleWarning;
        
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) {
                [self.audioRecorder deleteRecording:recording];
                [self.audioRecorder fetchRecordings];
                self.filteredRecordings = self.audioRecorder.recordings;
                [self.tableView reloadData];
                
                // 清空文本区域
                self.transcriptionTextView.string = @"";
                self.translationTextView.string = @"";
            }
        }];
    }
}

- (void)transcribeClicked:(id)sender {
    if (self.isTranscribing) {
        [self stopTranscription];
        return;
    }
    
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[selectedRow];
        [self startTranscriptionForRecording:recording];
    }
}

- (void)startTranscriptionForRecording:(Recording *)recording {
    if (!self.speechRecognizer || !self.speechRecognizer.isAvailable) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"failed";
        alert.informativeText = @"Please check the voice recognition permissions or network connection.";
        [alert runModal];
        return;
    }
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:recording.fileURL.path]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"File does not exist";
        alert.informativeText = @"The recording file may have been deleted or moved";
        [alert runModal];
        return;
    }
    
    self.transcriptionProgress.hidden = NO;
    [self.transcriptionProgress startAnimation:nil];
    self.transcriptionTextView.string = @"Analyzing audio...";
    self.isTranscribing = YES;
    
    // 创建识别请求
    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:recording.fileURL];
    request.shouldReportPartialResults = YES;
    request.taskHint = SFSpeechRecognitionTaskHintDictation;
    
    __weak typeof(self) weakSelf = self;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            if (error) {
                [strongSelf transcriptionFailedWithError:error];
                return;
            }
            
            if (result) {
                strongSelf.transcriptionTextView.string = result.bestTranscription.formattedString;
                
                if (result.isFinal) {
                    [strongSelf transcriptionCompleted];
                }
            }
        });
    }];
}

- (void)stopTranscription {
    [self.recognitionTask cancel];
    self.recognitionTask = nil;
    self.isTranscribing = NO;
    self.transcriptionProgress.hidden = YES;
    [self.transcriptionProgress stopAnimation:nil];
}

- (void)transcriptionCompleted {
    self.isTranscribing = NO;
    self.transcriptionProgress.hidden = YES;
    [self.transcriptionProgress stopAnimation:nil];
    self.transcriptionTextView.string = [NSString stringWithFormat:@"Text conversion completed:\n%@", self.transcriptionTextView.string];
}

- (void)transcriptionFailedWithError:(NSError *)error {
    self.isTranscribing = NO;
    self.transcriptionProgress.hidden = YES;
    [self.transcriptionProgress stopAnimation:nil];
    self.transcriptionTextView.string = [NSString stringWithFormat:@"Text conversion failed: %@", error.localizedDescription];
}

#pragma mark - 表格数据源和代理 (修复重复定义问题)
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.filteredRecordings.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    Recording *rec = self.filteredRecordings[row];
    NSString *identifier = tableColumn.identifier;
    
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] init];
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        textField.editable = NO;
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.autoresizingMask = NSViewWidthSizable;
        cellView.textField = textField;
        [cellView addSubview:textField];
    }
    
    // 设置文本字段的frame
    cellView.textField.frame = NSMakeRect(10, 5, tableColumn.width - 20, 20);
    
    if ([identifier isEqualToString:@"NameColumn"]) {
        cellView.textField.stringValue = [rec.name stringByDeletingPathExtension];
        cellView.textField.alignment = NSTextAlignmentLeft;
    }
    else if ([identifier isEqualToString:@"DateColumn"]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
        cellView.textField.stringValue = [formatter stringFromDate:rec.createdAt];
        cellView.textField.alignment = NSTextAlignmentLeft;
    }
    else if ([identifier isEqualToString:@"DurationColumn"]) {
        cellView.textField.stringValue = [self formattedTime:rec.duration];
        cellView.textField.alignment = NSTextAlignmentRight;
    }
    else if ([identifier isEqualToString:@"SizeColumn"]) {
        NSNumber *fileSize;
        [rec.fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        cellView.textField.stringValue = [self formattedFileSize:fileSize ? fileSize.doubleValue : 0];
        cellView.textField.alignment = NSTextAlignmentRight;
    }
    
    return cellView;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 30;
}

- (NSString *)formattedFileSize:(double)size {
    NSArray *units = @[@"B", @"KB", @"MB", @"GB"];
    NSInteger unitIndex = 0;
    while (size > 1024 && unitIndex < units.count - 1) {
        size /= 1024;
        unitIndex++;
    }
    return [NSString stringWithFormat:@"%.1f %@", size, units[unitIndex]];
}

- (NSString *)formattedTime:(NSTimeInterval)time {
    NSInteger minutes = (NSInteger)time / 60;
    NSInteger seconds = (NSInteger)time % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}

#pragma mark - 功能按钮事件
- (void)renameClicked:(id)sender {
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[selectedRow];
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"rename the file"];
        [alert addButtonWithTitle:@"yes"];
        [alert addButtonWithTitle:@"cancel"];
        
        NSTextField *inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        inputField.stringValue = [[recording.name stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"Recording-" withString:@""];
        [alert setAccessoryView:inputField];
        
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) {
                NSString *newName = [inputField.stringValue stringByAppendingPathExtension:@"m4a"];
                [self renameRecording:recording toName:newName];
            }
        }];
        
        [[alert window] makeFirstResponder:inputField];
    }
}

- (void)translateClicked:(id)sender {
    if (self.isTranscribing) {
        [self stopTranscription];
        return;
    }
    
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        
        // 检查是否有转文本结果
        if (self.transcriptionTextView.string.length > 0 &&
            ![self.transcriptionTextView.string hasPrefix:@"Analyzing"] &&
            ![self.transcriptionTextView.string hasPrefix:@"Text conversion failed"]) {
            
            [self translateRecordingText:self.transcriptionTextView.string targetLanguage:self.currentTargetLanguage];
        } else {
            // 如果没有有效的转文本结果，提示用户
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Valid text conversion results are required";
            alert.informativeText = @"Please successfully transcribe the recording file before translating it";
            [alert addButtonWithTitle:@"Confirm"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }
}

// 添加翻译方法实现
- (void)translateRecordingText:(NSString *)text targetLanguage:(NSString *)targetLang {
    self.translationTextView.string = @"Translating...";
    
    // 获取选中的语言名称用于显示
    NSString *selectedLangName = self.supportedLanguages[targetLang] ?: targetLang;
    
    [self translateWithGoogle:text targetLanguage:targetLang completion:^(NSString *translatedText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                // 如果Google翻译失败，使用备用翻译
                [self fallbackToMyMemoryTranslation:text sourceLanguage:@"zh-CN" targetLanguage:targetLang completion:^(NSString *fallbackTranslatedText, NSError *fallbackError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (fallbackError) {
                            self.translationTextView.string = [NSString stringWithFormat:@"Failed: %@", fallbackError.localizedDescription];
                        } else {
                            NSString *header = [NSString stringWithFormat:@"[Translated to %@]\n\n", selectedLangName];
                            self.translationTextView.string = [header stringByAppendingString:fallbackTranslatedText ?: @"Empty"];
                        }
                    });
                }];
            } else {
                NSString *header = [NSString stringWithFormat:@"[Translated to %@]\n\n", selectedLangName];
                self.translationTextView.string = [header stringByAppendingString:translatedText ?: @"Empty"];
            }
        });
    }];
}

// 添加语言选择器设置方法
- (void)setupLanguagePopup {
    [self.languagePopup removeAllItems];
    
    // 支持的语言列表
    self.supportedLanguages = @{
        @"en": @"English",
        @"zh-CN": @"简体中文",
        @"zh-TW": @"繁體中文",
        @"ja": @"日本語",
        @"ko": @"한국어",
        @"fr": @"Français",
        @"de": @"Deutsch",
        @"es": @"Español",
        @"ru": @"Русский",
        @"ar": @"العربية",
        @"pt": @"Português",
        @"it": @"Italiano",
        @"nl": @"Nederlands",
        @"tr": @"Türkçe",
        @"vi": @"Tiếng Việt",
        @"th": @"ไทย",
        @"hi": @"हिन्दी"
    };
    
    // 按语言名称排序
    NSArray *sortedLanguages = [self.supportedLanguages keysSortedByValueUsingSelector:@selector(compare:)];
    
    for (NSString *langCode in sortedLanguages) {
        NSString *langName = self.supportedLanguages[langCode];
        [self.languagePopup addItemWithTitle:langName];
        [[self.languagePopup lastItem] setRepresentedObject:langCode];
    }
    
    // 默认选择英文
    self.currentTargetLanguage = @"en";
    [self.languagePopup selectItemAtIndex:[sortedLanguages indexOfObject:@"en"]];
    
    // 添加选择事件
    [self.languagePopup setTarget:self];
    [self.languagePopup setAction:@selector(languagePopupChanged:)];
}

- (void)languagePopupChanged:(id)sender {
    NSString *selectedLangCode = [[self.languagePopup selectedItem] representedObject];
    if (selectedLangCode) {
        self.currentTargetLanguage = selectedLangCode;
        NSLog(@"Selected language: %@", self.supportedLanguages[selectedLangCode]);
        
        // 如果当前有翻译文本，自动重新翻译
        [self autoRetranslateIfNeeded];
    }
}

- (void)autoRetranslateIfNeeded {
    // 如果翻译文本框有内容且不是错误信息，自动重新翻译
    if (self.translationTextView.string.length > 0 &&
        ![self.translationTextView.string hasPrefix:@"Translating..."] &&
        ![self.translationTextView.string hasPrefix:@"Failed:"] &&
        self.transcriptionTextView.string.length > 0) {
        
        [self translateRecordingText:self.transcriptionTextView.string targetLanguage:self.currentTargetLanguage];
    }
}

// 统一的翻译方法（整合了原来的两个方法）
- (void)translateWithGoogle:(NSString *)text targetLanguage:(NSString *)targetLang completion:(void (^)(NSString *translatedText, NSError *error))completion {
    if (text.length == 0) {
        completion(@"", nil);
        return;
    }
    
    // 根据目标语言确定源语言
    NSString *sourceLang = @"zh-CN"; // 默认从简体中文翻译
    
    // 如果目标语言是中文，则源语言设为英文
    if ([targetLang hasPrefix:@"zh"]) {
        sourceLang = @"en";
    }
    
    // 正确编码文本
    NSString *encodedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSString *urlString = [NSString stringWithFormat:
                          @"https://translate.googleapis.com/translate_a/single?client=gtx&sl=%@&tl=%@&dt=t&q=%@",
                          sourceLang, targetLang, encodedText];
    
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // Google翻译失败，回退到MyMemory API
            [self fallbackToMyMemoryTranslation:text sourceLanguage:sourceLang targetLanguage:targetLang completion:completion];
            return;
        }
        
        @try {
            NSError *jsonError;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                [self fallbackToMyMemoryTranslation:text sourceLanguage:sourceLang targetLanguage:targetLang completion:completion];
                return;
            }
            
            NSString *translatedText = @"";
            if ([json isKindOfClass:[NSArray class]] && [json count] > 0) {
                NSArray *mainArray = json[0];
                NSMutableString *result = [NSMutableString string];
                
                for (id segment in mainArray) {
                    if ([segment isKindOfClass:[NSArray class]] && [segment count] > 0) {
                        NSString *textSegment = segment[0];
                        if ([textSegment isKindOfClass:[NSString class]]) {
                            [result appendString:textSegment];
                        }
                    }
                }
                translatedText = [result copy];
                
                // 确保文本正确解码
                translatedText = [translatedText stringByRemovingPercentEncoding] ?: translatedText;
            }
            
            // 语法修正
            translatedText = [self improveGrammar:translatedText targetLanguage:targetLang];
            
            completion(translatedText, nil);
        } @catch (NSException *exception) {
            [self fallbackToMyMemoryTranslation:text sourceLanguage:sourceLang targetLanguage:targetLang completion:completion];
        }
    }];
    
    [task resume];
}

// 备用翻译方法（MyMemory API）
- (void)fallbackToMyMemoryTranslation:(NSString *)text sourceLanguage:(NSString *)sourceLang targetLanguage:(NSString *)targetLang completion:(void (^)(NSString *translatedText, NSError *error))completion {
    
    // 正确编码文本
    NSString *encodedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSString *urlString = [NSString stringWithFormat:
                          @"https://api.mymemory.translated.net/get?q=%@&langpair=%@|%@",
                          encodedText, sourceLang, targetLang];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            completion(nil, jsonError);
            return;
        }
        
        // 获取翻译结果并解码
        NSString *translatedText = json[@"responseData"][@"translatedText"];
        if (translatedText) {
            // 确保文本正确解码
            translatedText = [translatedText stringByRemovingPercentEncoding];
            if (!translatedText) {
                translatedText = json[@"responseData"][@"translatedText"];
            }
            
            // 语法修正
            translatedText = [self improveGrammar:translatedText targetLanguage:targetLang];
            
            completion(translatedText, nil);
        } else {
            NSString *errorMsg = json[@"responseDetails"] ?: @"Translation failed";
            completion(nil, [NSError errorWithDomain:@"TranslationError" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMsg}]);
        }
    }];
    
    [task resume];
}

// 语法修正方法（保持不变）
- (NSString *)improveGrammar:(NSString *)text targetLanguage:(NSString *)targetLang {
    if ([targetLang isEqualToString:@"en"]) {
        // 英文语法修正规则
        NSString *improvedText = text;
        
        // 修正冠词使用
        improvedText = [improvedText stringByReplacingOccurrencesOfString:@" a bread" withString:@" some bread"];
        improvedText = [improvedText stringByReplacingOccurrencesOfString:@" a advice" withString:@" some advice"];
        improvedText = [improvedText stringByReplacingOccurrencesOfString:@" a information" withString:@" some information"];
        
        // 修正动词形式
        improvedText = [improvedText stringByReplacingOccurrencesOfString:@"give me my" withString:@"give me the"];
        
        // 修正句子结构
        if ([improvedText containsString:@"and give me"]) {
            improvedText = [improvedText stringByReplacingOccurrencesOfString:@"and give me" withString:@"and could you give me"];
        }
        
        // 确保首字母大写
        if (improvedText.length > 0) {
            improvedText = [improvedText stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                 withString:[[improvedText substringToIndex:1] uppercaseString]];
        }
        
        return improvedText;
    }
    
    return text; // 其他语言暂时不处理
}

// renameRecording方法保持不变
- (void)renameRecording:(Recording *)recording toName:(NSString *)newName {
    NSURL *newURL = [recording.fileURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:newName];
    NSError *error;
    [[NSFileManager defaultManager] moveItemAtURL:recording.fileURL toURL:newURL error:&error];
    if (error) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
    } else {
        recording.fileURL = newURL;
        recording.name = newName;
        [self.tableView reloadData];
        [self.audioRecorder fetchRecordings];
        self.filteredRecordings = self.audioRecorder.recordings;
    }
}

#pragma mark - 搜索功能
- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.searchField) {
        [self filterRecordings];
    }
}

- (void)filterRecordings {
    NSString *searchText = self.searchField.stringValue;
    if (searchText.length == 0) {
        self.filteredRecordings = self.audioRecorder.recordings;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", searchText];
        self.filteredRecordings = [self.audioRecorder.recordings filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

#pragma mark - 录音控制事件
- (void)micPermissionClicked:(id)sender {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                NSLog(@"Allowed");
            } else {
                NSLog(@"Refused");
            }
        });
    }];
}

- (void)startRecordingClicked:(id)sender {
    [self.audioRecorder requestPermissionAndStartRecording];
}

- (void)stopRecordingClicked:(id)sender {
    [self.audioRecorder stopRecording];
    [self.audioRecorder fetchRecordings];
    self.filteredRecordings = self.audioRecorder.recordings;
    [self.tableView reloadData];
}

- (void)playClicked:(id)sender {
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[selectedRow];
        
        // 如果已经有波形数据，使用指针位置，否则从头播放
        if (self.waveformData.count > 0) {
            NSTimeInterval startTime = self.playheadPosition * recording.duration;
            [self.audioRecorder playRecording:recording fromTime:startTime];
        } else {
            [self.audioRecorder playRecording:recording];
        }
    }
}

- (void)pauseClicked:(id)sender {
    [self.audioRecorder pausePlayback];
}

- (void)stopPlaybackClicked:(id)sender {
    [self.audioRecorder stopPlayback];
}

- (void)tableViewDoubleClick:(id)sender {
    NSInteger row = [self.tableView clickedRow];
    if (row >= 0 && row < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[row];
        [self.audioRecorder playRecording:recording];
    }
}

- (void)setupWaveformAreaInView:(NSView *)contentView {
    // 波形显示区域标题
    NSTextField *waveformLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 570, 400, 20)];
    waveformLabel.stringValue = @"Sound waveform:";
    waveformLabel.editable = NO;
    waveformLabel.bezeled = NO;
    waveformLabel.drawsBackground = NO;
    waveformLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [contentView addSubview:waveformLabel];
    
    // 波形显示视图
    self.waveformView = [[NSView alloc] initWithFrame:NSMakeRect(20, 520, 810, 40)];
    self.waveformView.wantsLayer = YES;
    self.waveformView.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    self.waveformView.layer.borderColor = [NSColor separatorColor].CGColor;
    self.waveformView.layer.borderWidth = 1.0;
    self.waveformView.layer.cornerRadius = 4.0;
    
    // 添加点击手势
    NSClickGestureRecognizer *clickGesture = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(waveformClicked:)];
    [self.waveformView addGestureRecognizer:clickGesture];
    
    // 添加拖拽手势
    NSPanGestureRecognizer *panGesture = [[NSPanGestureRecognizer alloc] initWithTarget:self action:@selector(waveformDragged:)];
    [self.waveformView addGestureRecognizer:panGesture];
    
    [contentView addSubview:self.waveformView];
    
    // 从指针位置播放按钮 - 放在波形标题旁边
    self.playFromCursorButton = [[NSButton alloc] initWithFrame:NSMakeRect(640, 570, 190, 25)];
    [self.playFromCursorButton setTitle:@"Play from here"];
    [self.playFromCursorButton setTarget:self];
    [self.playFromCursorButton setAction:@selector(playFromCursorClicked:)];
    [self.playFromCursorButton setEnabled:NO];
    self.playFromCursorButton.bezelStyle = NSBezelStyleRounded;
    [contentView addSubview:self.playFromCursorButton];
    
    // 初始播放指针位置
    self.playheadPosition = 0.0;
    
    // 初始绘制一个空的波形
    [self drawWaveform];
}

#pragma mark - 波形显示和交互

- (void)drawWaveform {
    // 清除之前的绘制
    for (CALayer *sublayer in self.waveformView.layer.sublayers.copy) {
        [sublayer removeFromSuperlayer];
    }
    
    if (!self.waveformData || self.waveformData.count == 0) {
        // 绘制空状态提示
        CATextLayer *emptyLayer = [CATextLayer layer];
        emptyLayer.frame = self.waveformView.bounds;
        emptyLayer.string = @"please choose a file to start";
        emptyLayer.foregroundColor = [NSColor tertiaryLabelColor].CGColor;
        emptyLayer.alignmentMode = kCAAlignmentCenter;
        emptyLayer.fontSize = 12;
        emptyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        [self.waveformView.layer addSublayer:emptyLayer];
        return;
    }
    
    // 绘制波形
    CGFloat width = self.waveformView.bounds.size.width;
    CGFloat height = self.waveformView.bounds.size.height;
    CGFloat centerY = height / 2;
    CGFloat barWidth = MAX(1.0, width / self.waveformData.count);
    
    // 绘制中心线
    CALayer *centerLine = [CALayer layer];
    centerLine.frame = CGRectMake(0, centerY - 0.5, width, 1);
    centerLine.backgroundColor = [NSColor separatorColor].CGColor;
    [self.waveformView.layer addSublayer:centerLine];
    
    // 绘制波形条
    for (NSInteger i = 0; i < self.waveformData.count; i++) {
        @autoreleasepool {
            CGFloat amplitude = [self.waveformData[i] floatValue];
            CGFloat barHeight = amplitude * height * 0.8; // 80% 的高度
            
            if (barHeight > 1.0) { // 只绘制有高度的条形
                CALayer *barLayer = [CALayer layer];
                CGFloat x = i * barWidth;
                barLayer.frame = CGRectMake(x, centerY - barHeight / 2, barWidth - 0.5, barHeight);
                
                // 根据振幅设置颜色
                if (amplitude > 0.6) {
                    barLayer.backgroundColor = [NSColor systemRedColor].CGColor;
                } else if (amplitude > 0.3) {
                    barLayer.backgroundColor = [NSColor systemOrangeColor].CGColor;
                } else {
                    barLayer.backgroundColor = [NSColor systemBlueColor].CGColor;
                }
                
                barLayer.cornerRadius = 1.0;
                [self.waveformView.layer addSublayer:barLayer];
            }
        }
    }
    
    // 绘制播放指针
    [self drawPlayhead];
}

- (void)drawPlayhead {
    // 移除旧的指针
    for (CALayer *sublayer in self.waveformView.layer.sublayers.copy) {
        if ([sublayer.name isEqualToString:@"playhead"]) {
            [sublayer removeFromSuperlayer];
        }
    }
    
    CGFloat width = self.waveformView.bounds.size.width;
    CGFloat height = self.waveformView.bounds.size.height;
    CGFloat xPosition = self.playheadPosition * width;
    
    // 创建指针
    CALayer *playheadLayer = [CALayer layer];
    playheadLayer.name = @"playhead";
    playheadLayer.frame = CGRectMake(xPosition - 1, 0, 2, height);
    playheadLayer.backgroundColor = [NSColor systemRedColor].CGColor;
    playheadLayer.shadowColor = [NSColor blackColor].CGColor;
    playheadLayer.shadowOffset = CGSizeMake(0, 0);
    playheadLayer.shadowOpacity = 0.5;
    playheadLayer.shadowRadius = 1.0;
    playheadLayer.zPosition = 100; // 确保在最上层
    
    [self.waveformView.layer addSublayer:playheadLayer];
}

- (void)waveformClicked:(NSClickGestureRecognizer *)gesture {
    if (gesture.state == NSGestureRecognizerStateEnded) {
        NSPoint location = [gesture locationInView:self.waveformView];
        [self updatePlayheadPositionWithLocation:location];
    }
}

- (void)waveformDragged:(NSPanGestureRecognizer *)gesture {
    NSPoint location = [gesture locationInView:self.waveformView];
    [self updatePlayheadPositionWithLocation:location];
}

- (void)updatePlayheadPositionWithLocation:(NSPoint)location {
    CGFloat width = self.waveformView.bounds.size.width;
    self.playheadPosition = MAX(0.0, MIN(1.0, location.x / width));
    [self drawPlayhead];
}

- (void)playFromCursorClicked:(id)sender {
    NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
        Recording *recording = self.filteredRecordings[selectedRow];
        NSTimeInterval startTime = self.playheadPosition * recording.duration;
        
        [self.audioRecorder playRecording:recording fromTime:startTime];
    }
}

- (void)updateWaveformForSelectedRecording {
    NSInteger selectedRow = self.tableView.selectedRow;
        NSLog(@"Update waveform display, selected line: %ld", selectedRow);
        
        if (selectedRow >= 0 && selectedRow < self.filteredRecordings.count) {
            Recording *recording = self.filteredRecordings[selectedRow];
            NSLog(@"Starting to analyze recording file: %@", recording.name);

        // 先显示加载状态
        self.waveformData = @[];
        [self drawWaveform];
        self.playFromCursorButton.enabled = NO;
        
        // 在后台线程分析波形数据（使用异步版本）
        [self.audioRecorder analyzeWaveformForRecording:recording completion:^(NSArray *waveformData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (waveformData && waveformData.count > 0) {
                    self.waveformData = waveformData;
                    [self drawWaveform];
                    self.playFromCursorButton.enabled = YES;
                    NSLog(@"Waveform data loaded successfully, totaling %ld data points", waveformData.count);
                } else {
                    NSLog(@"Waveform data loading failed");
                    // 使用模拟数据作为后备
                    self.waveformData = [self generateFallbackWaveformData];
                    [self drawWaveform];
                    self.playFromCursorButton.enabled = YES;
                }
            });
        }];
    } else {
        self.waveformData = @[];
        [self drawWaveform];
        self.playFromCursorButton.enabled = NO;
    }
}

// 生成后备波形数据
- (NSArray *)generateFallbackWaveformData {
    NSMutableArray *fallbackData = [NSMutableArray array];
    for (NSInteger i = 0; i < 150; i++) {
        float value = 0.1 + 0.3 * sin(i * 0.1) + (float)rand() / RAND_MAX * 0.2;
        [fallbackData addObject:@(MIN(0.8, value))];
    }
    return [fallbackData copy];
}

#pragma mark - NSApplication
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - 结束进程与清理
- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // 停止录音
    if (self.audioRecorder.isRecording) {
        [self.audioRecorder stopRecording];
    }
    // 停止音频播放
    if (self.audioRecorder.isPlaying) {
        [self.audioRecorder stopPlayback];
    }
    // 取消语音识别任务
    if (self.isTranscribing) {
        [self stopTranscription];
    }
    // 释放任何其它需要清理的资源
    // ...
    
    if (self.statusUpdateTimer) {
        [self.statusUpdateTimer invalidate];
        self.statusUpdateTimer = nil;
    }
}

@end

