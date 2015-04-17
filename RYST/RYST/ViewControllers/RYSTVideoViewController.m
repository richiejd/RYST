//
//  RYSTVideoViewController.m
//  RYST
//
//  Created by Richie Davis on 4/15/15.
//  Copyright (c) 2015 Vissix. All rights reserved.
//

#import "RYSTVideoViewController.h"
#import "RYSTIntroViewController.h"
#import "RYSTCameraView.h"
#import "RYSTRecordButton.h"

#import "UIView+RJDConvenience.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;

@interface RYSTVideoViewController () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, strong) RYSTIntroViewController *childViewController;
@property (nonatomic) BOOL shouldDisplayIntro;

@property (nonatomic, strong) RYSTCameraView *previewView;
@property (nonatomic, strong) RYSTRecordButton *recordButton;
@property (nonatomic, strong) UIButton *flipCameraButton;
@property (nonatomic, strong) UIButton *pickAffirmationButton;
@property (nonatomic, strong) UIButton *viewAffirmationsButton;
@property (nonatomic, strong) UILabel *affirmationLabel;

@property (nonatomic, strong) NSString *affirmationString;

// recording session management
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;

// utilities
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;

@end

@implementation RYSTVideoViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
  return [[self session] isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
  return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (instancetype)initShouldDisplayIntro:(BOOL)shouldDisplayIntro
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _shouldDisplayIntro = shouldDisplayIntro;
  }

  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  _previewView = [[RYSTCameraView alloc] initWithFrame:self.view.frame];
  [self.view addSubview:_previewView];

  _recordButton = [[RYSTRecordButton alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
  [_recordButton addTarget:self action:@selector(toggleMovieRecording) forControlEvents:UIControlEventTouchUpInside];
  _recordButton.center = CGPointMake(self.view.center.x, CGRectGetHeight(self.view.frame) - 80);
  [self.view addSubview:_recordButton];

  _flipCameraButton = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(self.view.bounds) - 70, 30, 50, 50)];
  [_flipCameraButton setBackgroundImage:[UIImage imageNamed:@"rotate-camera-orange"] forState:UIControlStateNormal];
  [_flipCameraButton addTarget:self action:@selector(changeCamera) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_flipCameraButton];

  _pickAffirmationButton = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(self.view.bounds) - 70, CGRectGetHeight(self.view.bounds) - 70, 50, 50)];
  [_pickAffirmationButton setBackgroundImage:[UIImage imageNamed:@"pointer-blue"] forState:UIControlStateNormal];
  [_pickAffirmationButton addTarget:self action:@selector(changeCamera) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_pickAffirmationButton];

  _viewAffirmationsButton = [[UIButton alloc] initWithFrame:CGRectMake(20, CGRectGetHeight(self.view.bounds) - 65, 45, 45)];
  [_viewAffirmationsButton setBackgroundImage:[UIImage imageNamed:@"movie-yellow"] forState:UIControlStateNormal];
  [_viewAffirmationsButton addTarget:self action:@selector(changeCamera) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_viewAffirmationsButton];

  _affirmationString = NSLocalizedString(@"Pick an affirmation!", nil);

  _affirmationLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 20)];
  _affirmationLabel.backgroundColor = [UIColor colorWithRed:174.0f/255.0f green:0.0f/255.0f blue:220.0f/255.0f alpha:1.0f];
  _affirmationLabel.font = [UIFont fontWithName:@"Avenir-Roman" size:12.0f];
  _affirmationLabel.textColor = [UIColor whiteColor];
  _affirmationLabel.textAlignment = NSTextAlignmentCenter;
  _affirmationLabel.text = self.affirmationString;
  _affirmationLabel.alpha = 0.5f;
  [self.view addSubview:_affirmationLabel];
  

  // Create the AVCaptureSession
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  self.session = session;

  // Setup the preview view
  self.previewView.session = session;

  // Check for device authorization
  [self checkDeviceAuthorizationStatus];

  dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
  [self setSessionQueue:sessionQueue];

  dispatch_async(sessionQueue, ^{
    [self setBackgroundRecordingID:UIBackgroundTaskInvalid];

    NSError *error = nil;

    AVCaptureDevice *videoDevice = [RYSTVideoViewController deviceWithMediaType:AVMediaTypeVideo
                                                             preferringPosition:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];

    if (error) NSLog(@"%@", error);

    if ([session canAddInput:videoDeviceInput]) {
      [session addInput:videoDeviceInput];
      [self setVideoDeviceInput:videoDeviceInput];

      dispatch_async(dispatch_get_main_queue(), ^{
        [[(AVCaptureVideoPreviewLayer *)self.previewView.layer connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
      });
    }

    AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];

    if (error) NSLog(@"%@", error);

    if ([session canAddInput:audioDeviceInput]) [session addInput:audioDeviceInput];

    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:movieFileOutput]) {
      [session addOutput:movieFileOutput];
      AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
      if ([connection isVideoStabilizationSupported]) connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
      [self setMovieFileOutput:movieFileOutput];
    }
  });

  if (self.shouldDisplayIntro) {
    RYSTIntroViewController *vc = [[RYSTIntroViewController alloc] init];
    [self addChildViewController:vc];
    [self.view addSubview:vc.view];
    [vc didMoveToParentViewController:self];
    vc.presenter = self;

    _childViewController = vc;
  }
}

- (void)viewWillAppear:(BOOL)animated
{
  if (!self.shouldDisplayIntro) {
    [self showCameraView];
  }
}

- (void)viewDidDisappear:(BOOL)animated
{
  dispatch_async([self sessionQueue], ^{
    [[self session] stopRunning];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
    [[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];

    [self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
    [self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
  });
}

- (void)showCameraView
{
  dispatch_async([self sessionQueue], ^{
    [self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
    [self addObserver:self forKeyPath:@"movieFileOutput.recording" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:RecordingContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];

    __weak typeof(self) weakSelf = self;
    [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
      typeof(self) strongSelf = weakSelf;
      dispatch_async([strongSelf sessionQueue], ^{
        // Manually restarting the session since it must have been stopped due to an error.
        [[strongSelf session] startRunning];
      });
    }]];
    [[self session] startRunning];
  });
}

- (void)dismissChild:(UIViewController *)child
{
  if (child == self.childViewController) {
    [UIView animateWithDuration:0.3f
                     animations:^{
                       self.childViewController.view.layer.transform = CATransform3DScale(CATransform3DIdentity,
                                                                                          0.01f,
                                                                                          0.01f,
                                                                                          1.0f);
                     } completion:^(BOOL finished) {
                       [self.childViewController willMoveToParentViewController:nil];
                       [self.childViewController.view removeFromSuperview];
                       [self.childViewController removeFromParentViewController];
                       [self showCameraView];
                     }];
  } // abort if not
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
  return UIInterfaceOrientationMaskPortrait;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (context == RecordingContext) {
    BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (isRecording) {
        [self.flipCameraButton setEnabled:NO];
        [self.recordButton setEnabled:YES];
      } else {
        [self.flipCameraButton setEnabled:YES];
        [self.recordButton setEnabled:YES];
      }
    });
  } else if (context == SessionRunningAndDeviceAuthorizedContext) {
    BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (isRunning) {
        [self.flipCameraButton setEnabled:YES];
        [self.recordButton setEnabled:YES];
      } else {
        [self.flipCameraButton setEnabled:NO];
        [self.recordButton setEnabled:NO];
      }
    });
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

#pragma mark Actions

- (void)toggleMovieRecording
{
  [self.recordButton toggleRecording];

  [self.recordButton setEnabled:NO];

  dispatch_async([self sessionQueue], ^{
    if (![self.movieFileOutput isRecording]) {
      [self setLockInterfaceRotation:YES];

      if ([[UIDevice currentDevice] isMultitaskingSupported]) {
        [self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil]];
      }

      // Update the orientation on the movie file output video connection before starting recording.
      [[self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)self.previewView.layer connection] videoOrientation]];

      // Turning OFF flash for video recording
      [RYSTVideoViewController setFlashMode:AVCaptureFlashModeOff forDevice:[[self videoDeviceInput] device]];

      // Start recording to a temporary file.
      NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"movie" stringByAppendingPathExtension:@"mov"]];
      [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
    } else {
      [self.movieFileOutput stopRecording];
    }
  });
}

- (void)changeCamera
{
  [self.flipCameraButton setEnabled:NO];
  [self.recordButton setEnabled:NO];

  dispatch_async([self sessionQueue], ^{
    AVCaptureDevice *currentVideoDevice = [[self videoDeviceInput] device];
    AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
    AVCaptureDevicePosition currentPosition = [currentVideoDevice position];

    switch (currentPosition) {
      case AVCaptureDevicePositionUnspecified:
        preferredPosition = AVCaptureDevicePositionBack;
        break;
      case AVCaptureDevicePositionBack:
        preferredPosition = AVCaptureDevicePositionFront;
        break;
      case AVCaptureDevicePositionFront:
        preferredPosition = AVCaptureDevicePositionBack;
        break;
    }

    AVCaptureDevice *videoDevice = [RYSTVideoViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];

    [[self session] beginConfiguration];

    [[self session] removeInput:[self videoDeviceInput]];
    if ([[self session] canAddInput:videoDeviceInput]) {
      [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];

      [RYSTVideoViewController setFlashMode:AVCaptureFlashModeAuto forDevice:videoDevice];
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];

      [[self session] addInput:videoDeviceInput];
      [self setVideoDeviceInput:videoDeviceInput];
    } else {
      [[self session] addInput:[self videoDeviceInput]];
    }

    [[self session] commitConfiguration];

    dispatch_async(dispatch_get_main_queue(), ^{
      [self.flipCameraButton setEnabled:YES];
      [self.recordButton setEnabled:YES];
    });
  });
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
  CGPoint devicePoint = CGPointMake(.5, .5);
  [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

#pragma mark File Output Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  if (error) NSLog(@"%@", error);

  [self setLockInterfaceRotation:NO];

  UIBackgroundTaskIdentifier backgroundRecordingID = [self backgroundRecordingID];
  [self setBackgroundRecordingID:UIBackgroundTaskInvalid];

  [[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
    if (error) NSLog(@"%@", error);
    [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
    if (backgroundRecordingID != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
  }];
}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
  dispatch_async([self sessionQueue], ^{
    AVCaptureDevice *device = [[self videoDeviceInput] device];
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
      if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode]) {
        [device setFocusMode:focusMode];
        [device setFocusPointOfInterest:point];
      }
      if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode]) {
        [device setExposureMode:exposureMode];
        [device setExposurePointOfInterest:point];
      }
      [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
      [device unlockForConfiguration];
    } else {
      NSLog(@"%@", error);
    }
  });
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
  if ([device hasFlash] && [device isFlashModeSupported:flashMode]) {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
      [device setFlashMode:flashMode];
      [device unlockForConfiguration];
    } else {
      NSLog(@"%@", error);
    }
  }
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
  NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
  AVCaptureDevice *captureDevice = [devices firstObject];

  for (AVCaptureDevice *device in devices) {
    if ([device position] == position) return device;
  }

  return captureDevice;
}

#pragma mark UI

- (void)checkDeviceAuthorizationStatus
{
  NSString *mediaType = AVMediaTypeVideo;

  [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
    if (granted) {
      [self setDeviceAuthorized:YES];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        [[[UIAlertView alloc] initWithTitle:@"Oh No!"
                                    message:@"RYST needs to access your camera to share your positivity, please update your camera settings."
                                   delegate:self
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        [self setDeviceAuthorized:NO];
      });
    }}];
}

@end