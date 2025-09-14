#import "VideoFilterController.h"
#import <nosmai/Nosmai.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>

// Constants
static NSString * const kNosmaiAPIKey = @"API-KEY";


static const float kDefaultButtonSize = 50.0f;
static const float kDefaultMargin = 20.0f;
static NSString * const kFilterCellIdentifier = @"FilterCell";
static NSString * const kPlaceholderCellIdentifier = @"PlaceholderCell";

// Static image cache to prevent reloading previews
static NSMutableDictionary *imageCache = nil;


@interface FilterPlaceholderCell : UICollectionViewCell
@end

@implementation FilterPlaceholderCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        // --- Create Modern Shimmer Container ---
        UIView *shimmerContainer = [[UIView alloc] init];
        shimmerContainer.translatesAutoresizingMaskIntoConstraints = NO;
        shimmerContainer.layer.cornerRadius = 12.0;
        shimmerContainer.clipsToBounds = YES;
        [self.contentView addSubview:shimmerContainer];
        
        // --- Add Gradient Background ---
        CAGradientLayer *gradientLayer = [CAGradientLayer layer];
        gradientLayer.colors = @[
            (id)[UIColor colorWithWhite:0.15 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.25 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.15 alpha:1.0].CGColor
        ];
        gradientLayer.startPoint = CGPointMake(0, 0);
        gradientLayer.endPoint = CGPointMake(1, 1);
        gradientLayer.frame = CGRectMake(0, 0, 70, 110);
        [shimmerContainer.layer addSublayer:gradientLayer];
        
        // --- Add Shimmer Effect ---
        CAGradientLayer *shimmerLayer = [CAGradientLayer layer];
        shimmerLayer.colors = @[
            (id)[UIColor colorWithWhite:0.2 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:0.8 alpha:0.3].CGColor,
            (id)[UIColor colorWithWhite:0.2 alpha:0.0].CGColor
        ];
        shimmerLayer.startPoint = CGPointMake(0, 0.5);
        shimmerLayer.endPoint = CGPointMake(1, 0.5);
        shimmerLayer.frame = CGRectMake(-70, 0, 70, 110);
        [shimmerContainer.layer addSublayer:shimmerLayer];
        
        // --- Animate Shimmer ---
        CABasicAnimation *shimmerAnimation = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        shimmerAnimation.fromValue = @(-70);
        shimmerAnimation.toValue = @(140);
        shimmerAnimation.duration = 1.5;
        shimmerAnimation.repeatCount = INFINITY;
        shimmerAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [shimmerLayer addAnimation:shimmerAnimation forKey:@"shimmer"];
        
        // --- Add Subtle Border ---
        shimmerContainer.layer.borderWidth = 1.0;
        shimmerContainer.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.6].CGColor;
        
        // --- Add Constraints ---
        [NSLayoutConstraint activateConstraints:@[
            [shimmerContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [shimmerContainer.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [shimmerContainer.widthAnchor constraintEqualToConstant:70.0], // Match new cell size
            [shimmerContainer.heightAnchor constraintEqualToConstant:110.0],
        ]];
    }
    return self;
}

@end


// MARK: - Beauty Filter Data Structures and Cell Classes

// Beauty filter type enum
typedef NS_ENUM(NSInteger, BeautyFilterType) {
    BeautyFilterTypeSlider,
    BeautyFilterTypeToggle
};

// Beauty filter data model
@interface BeautyFilterModel : NSObject
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSString *iconName;
@property (nonatomic, strong) NSString *category;
@property (nonatomic, assign) BeautyFilterType type;
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@property (nonatomic, assign) float defaultValue;
@property (nonatomic, assign) float currentValue;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, strong) NSString *methodName;
@end

@implementation BeautyFilterModel
@end

// Beauty filter collection view cell
@interface BeautyFilterCell : UICollectionViewCell
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *selectionIndicator;
@property (nonatomic, assign) BOOL isActive;
- (void)configureWithFilter:(BeautyFilterModel *)filter;
@end

@implementation BeautyFilterCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupCell];
    }
    return self;
}

- (void)setupCell {
    // Container view with improved glass effect
    _containerView = [[UIView alloc] init];
    _containerView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    _containerView.layer.cornerRadius = 10;
    _containerView.layer.borderWidth = 1;
    _containerView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_containerView];
    
    // Icon image view with better sizing
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    _iconImageView.tintColor = [UIColor whiteColor];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [_containerView addSubview:_iconImageView];
    
    // Name label with improved typography
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.textColor = [UIColor whiteColor];
    _nameLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.numberOfLines = 2;
    _nameLabel.adjustsFontSizeToFitWidth = YES;
    _nameLabel.minimumScaleFactor = 0.8;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_nameLabel];
    
    // Selection indicator with improved styling
    _selectionIndicator = [[UIView alloc] init];
    _selectionIndicator.backgroundColor = [UIColor systemBlueColor];
    _selectionIndicator.layer.cornerRadius = 1.5;
    _selectionIndicator.hidden = YES;
    _selectionIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_selectionIndicator];
    
    // Improved constraints with better spacing
    [NSLayoutConstraint activateConstraints:@[
        // Container - dynamic height based on cell size
        [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
        [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],
        [_containerView.heightAnchor constraintEqualToAnchor:_containerView.widthAnchor], // Square aspect ratio
        
        // Icon - responsive sizing
        [_iconImageView.centerXAnchor constraintEqualToAnchor:_containerView.centerXAnchor],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
        [_iconImageView.widthAnchor constraintEqualToAnchor:_containerView.widthAnchor multiplier:0.5],
        [_iconImageView.heightAnchor constraintEqualToAnchor:_iconImageView.widthAnchor],
        
        // Name label with better spacing
        [_nameLabel.topAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:3],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_nameLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor],
        
        // Selection indicator with responsive width
        [_selectionIndicator.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-2],
        [_selectionIndicator.centerXAnchor constraintEqualToAnchor:_containerView.centerXAnchor],
        [_selectionIndicator.widthAnchor constraintEqualToAnchor:_containerView.widthAnchor multiplier:0.6],
        [_selectionIndicator.heightAnchor constraintEqualToConstant:3]
    ]];
}

- (void)configureWithFilter:(BeautyFilterModel *)filter {
    // Configure icon
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    self.iconImageView.image = [UIImage systemImageNamed:filter.iconName withConfiguration:config];
    
    // Configure name
    self.nameLabel.text = filter.displayName;
    
    // Update active state
    [self setActive:filter.isActive animated:NO];
}

- (void)setActive:(BOOL)active animated:(BOOL)animated {
    self.isActive = active;
    
    void (^updateBlock)(void) = ^{
        if (active) {
            self.containerView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
            self.containerView.layer.borderColor = [UIColor systemBlueColor].CGColor;
            self.containerView.layer.borderWidth = 2;
            self.selectionIndicator.hidden = NO;
            self.iconImageView.tintColor = [UIColor systemBlueColor];
            self.nameLabel.textColor = [UIColor systemBlueColor];
        } else {
            self.containerView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
            self.containerView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
            self.containerView.layer.borderWidth = 1;
            self.selectionIndicator.hidden = YES;
            self.iconImageView.tintColor = [UIColor whiteColor];
            self.nameLabel.textColor = [UIColor whiteColor];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.2 animations:updateBlock];
    } else {
        updateBlock();
    }
}

@end

// MARK: - FilterCollectionViewCell (Carousel Style - Polished)

@interface FilterCollectionViewCell : UICollectionViewCell
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UIImageView *downloadIcon;
@property (strong, nonatomic) UIActivityIndicatorView *progressIndicator;
@property (strong, nonatomic) UIProgressView *downloadProgress;
@property (strong, nonatomic) UIImageView *previewImageView;
@property (strong, nonatomic) UIView *overlayView;
- (void)configureWithFilterInfo:(NSDictionary *)filterInfo isDownloading:(BOOL)isDownloading isSelected:(BOOL)isSelected;
- (void)configureForClearButton;
@end



@implementation FilterCollectionViewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self setupCell];
    return self;
}

- (void)setupCell {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    
    // The main circular view for the preview
    _previewImageView = [[UIImageView alloc] init];
    _previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    _previewImageView.clipsToBounds = YES;
    _previewImageView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _previewImageView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor; // Subtle border
    _previewImageView.layer.borderWidth = 1.5f;
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_previewImageView];
    
    // Box shape with rounded corners instead of circle
    _previewImageView.layer.cornerRadius = 12.0f;
    
    // Overlay for non-centered items to dim them
    _overlayView = [[UIView alloc] init];
    _overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    _overlayView.layer.cornerRadius = 12.0f; // Match preview image corner radius
    _overlayView.hidden = YES;
    _overlayView.translatesAutoresizingMaskIntoConstraints = NO;
    [_previewImageView addSubview:_overlayView];
    
    // Title Label with a shadow for readability
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightBold];
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _titleLabel.layer.shadowRadius = 3.0;
    _titleLabel.layer.shadowOpacity = 0.8;
    _titleLabel.layer.shadowOffset = CGSizeMake(0, 1);
    [self.contentView addSubview:_titleLabel];
    
    // Download/Progress indicators
    _downloadIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"]];
    _downloadIcon.tintColor = [UIColor whiteColor];
    _downloadIcon.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    _downloadIcon.layer.cornerRadius = 8;
    _downloadIcon.hidden = YES;
    _downloadIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_downloadIcon];
    
    // Small progress indicator for corner
    _progressIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _progressIndicator.hidesWhenStopped = YES;
    _progressIndicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    _progressIndicator.layer.cornerRadius = 8;
    _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_progressIndicator];
    
    // Add download progress view for corner
    _downloadProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _downloadProgress.progressTintColor = [UIColor systemBlueColor];
    _downloadProgress.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    _downloadProgress.layer.cornerRadius = 2;
    _downloadProgress.clipsToBounds = YES;
    _downloadProgress.hidden = YES;
    _downloadProgress.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_downloadProgress];
    
    [NSLayoutConstraint activateConstraints:@[
        [_previewImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_previewImageView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [_previewImageView.widthAnchor constraintEqualToConstant:55],
        [_previewImageView.heightAnchor constraintEqualToConstant:55],
        
        [_overlayView.topAnchor constraintEqualToAnchor:_previewImageView.topAnchor],
        [_overlayView.leadingAnchor constraintEqualToAnchor:_previewImageView.leadingAnchor],
        [_overlayView.trailingAnchor constraintEqualToAnchor:_previewImageView.trailingAnchor],
        [_overlayView.bottomAnchor constraintEqualToAnchor:_previewImageView.bottomAnchor],
        
        [_titleLabel.topAnchor constraintEqualToAnchor:_previewImageView.bottomAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // Download icon in top-right corner
        [_downloadIcon.topAnchor constraintEqualToAnchor:_previewImageView.topAnchor constant:2],
        [_downloadIcon.trailingAnchor constraintEqualToAnchor:_previewImageView.trailingAnchor constant:-2],
        [_downloadIcon.widthAnchor constraintEqualToConstant:16],
        [_downloadIcon.heightAnchor constraintEqualToConstant:16],
        
        // Progress indicator in top-right corner
        [_progressIndicator.topAnchor constraintEqualToAnchor:_previewImageView.topAnchor constant:2],
        [_progressIndicator.trailingAnchor constraintEqualToAnchor:_previewImageView.trailingAnchor constant:-2],
        [_progressIndicator.widthAnchor constraintEqualToConstant:16],
        [_progressIndicator.heightAnchor constraintEqualToConstant:16],
        
        // Download progress bar at bottom of preview
        [_downloadProgress.bottomAnchor constraintEqualToAnchor:_previewImageView.bottomAnchor constant:-2],
        [_downloadProgress.leadingAnchor constraintEqualToAnchor:_previewImageView.leadingAnchor constant:2],
        [_downloadProgress.trailingAnchor constraintEqualToAnchor:_previewImageView.trailingAnchor constant:-2],
        [_downloadProgress.heightAnchor constraintEqualToConstant:4],
    ]];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    // The main selection is indicated by the scaling transform from the scroll view.
    // A thick border is no longer needed and looks cleaner without it.
}



-(void)configureForClearButton {
    // Set the text and clean the view
    self.titleLabel.text = @"None";
    self.previewImageView.image = nil;
    
    
    // Use a darker, more refined background color
    self.previewImageView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    
    // Remove old content if it exists
    for (UIView *subview in self.previewImageView.subviews) {
        if (subview != self.overlayView) {  // FIX: Don't remove overlayView
            [subview removeFromSuperview];
        }
    }
    
    
    UIView *iconContainer = [[UIView alloc] init];
    iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconContainer.backgroundColor = [UIColor clearColor];
    [self.previewImageView addSubview:iconContainer];
    
    
    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.centerXAnchor constraintEqualToAnchor:self.previewImageView.centerXAnchor],
        [iconContainer.centerYAnchor constraintEqualToAnchor:self.previewImageView.centerYAnchor],
        [iconContainer.widthAnchor constraintEqualToAnchor:self.previewImageView.widthAnchor multiplier:0.6],
        [iconContainer.heightAnchor constraintEqualToAnchor:self.previewImageView.heightAnchor multiplier:0.6],
    ]];
    
    // Create a stylish "no filter" icon - a slashed circle
    // Method 1: Using UIImageView with system image (iOS 13+)
    UIImageView *noFilterIcon = [[UIImageView alloc] init];
    noFilterIcon.translatesAutoresizingMaskIntoConstraints = NO;
    noFilterIcon.contentMode = UIViewContentModeScaleAspectFit;
    
    // Use SF Symbol for a more polished look
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightLight];
    UIImage *iconImage = [UIImage systemImageNamed:@"xmark.circle" withConfiguration:config];
    noFilterIcon.image = iconImage;
    noFilterIcon.tintColor = [UIColor whiteColor];
    
    [iconContainer addSubview:noFilterIcon];
    
    [NSLayoutConstraint activateConstraints:@[
        [noFilterIcon.topAnchor constraintEqualToAnchor:iconContainer.topAnchor],
        [noFilterIcon.leadingAnchor constraintEqualToAnchor:iconContainer.leadingAnchor],
        [noFilterIcon.trailingAnchor constraintEqualToAnchor:iconContainer.trailingAnchor],
        [noFilterIcon.bottomAnchor constraintEqualToAnchor:iconContainer.bottomAnchor],
    ]];
    
    // Add subtle inner shadow to preview image view for depth
    CALayer *layer = self.previewImageView.layer;
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOffset = CGSizeMake(0, 2);
    layer.shadowOpacity = 0.5;
    layer.shadowRadius = 4;
    
    // Add subtle reflection/highlight for a polished look
    UIView *highlightView = [[UIView alloc] init];
    highlightView.translatesAutoresizingMaskIntoConstraints = NO;
    highlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    highlightView.layer.cornerRadius = 10;
    [self.previewImageView addSubview:highlightView];
    
    [NSLayoutConstraint activateConstraints:@[
        [highlightView.topAnchor constraintEqualToAnchor:self.previewImageView.topAnchor constant:8],
        [highlightView.leadingAnchor constraintEqualToAnchor:self.previewImageView.leadingAnchor constant:15],
        [highlightView.trailingAnchor constraintEqualToAnchor:self.previewImageView.trailingAnchor constant:-15],
        [highlightView.heightAnchor constraintEqualToConstant:10],
    ]];
    
    // Hide download-related elements
    self.downloadIcon.hidden = YES;
    self.progressIndicator.hidden = YES;
}



- (void)configureWithFilterInfo:(NSDictionary *)filterInfo isDownloading:(BOOL)isDownloading isSelected:(BOOL)isSelected {
    // IMPORTANT: Remove ALL subviews from previewImageView EXCEPT overlayView
    for (UIView *subview in self.previewImageView.subviews) {
        if (subview != self.overlayView) {
            [subview removeFromSuperview];
        }
    }
    
    // Reset the preview image view's properties
    self.previewImageView.layer.shadowOpacity = 0;
    
    // Now configure the cell normally
    self.titleLabel.text = filterInfo[@"displayName"];
    
    // DON'T set image here - it will be loaded asynchronously
    // Just set background color
    self.previewImageView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    
    if ([filterInfo[@"type"] isEqualToString:@"cloud"] && ![filterInfo[@"isDownloaded"] boolValue]) {
        // Cloud filter that needs downloading
        if (isDownloading) {
            // Show progress indicator and progress bar
            self.downloadIcon.hidden = YES;
            self.downloadProgress.hidden = NO;
            self.downloadProgress.progress = 0.0;
            [self.progressIndicator startAnimating];
//            NSLog(@"🔄 Starting download UI for: %@", filterInfo[@"displayName"]);
        } else {
            // Show download icon only
            self.downloadIcon.hidden = NO;
            self.downloadProgress.hidden = YES;
            [self.progressIndicator stopAnimating];
        }
    } else {
        // Downloaded or local filter - hide all download indicators
        self.downloadIcon.hidden = YES;
        self.downloadProgress.hidden = YES;
        [self.progressIndicator stopAnimating];
    }
    
    // Apply selection highlighting
    if (isSelected) {
        self.previewImageView.layer.borderColor = [UIColor systemBlueColor].CGColor;
        self.previewImageView.layer.borderWidth = 3.0f;
    } else {
        self.previewImageView.layer.borderColor = [UIColor clearColor].CGColor;
        self.previewImageView.layer.borderWidth = 0.0f;
    }
}

// Method to update download progress
- (void)updateDownloadProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.downloadProgress.hidden) {
            self.downloadProgress.progress = progress;
            NSLog(@"📊 Download progress updated: %.1f%%", progress * 100);
        }
    });
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // Clean up everything when cell is about to be reused
    // DON'T reset previewImageView.image here - let cellForItemAtIndexPath handle it with cache
    self.titleLabel.text = nil;
    self.downloadIcon.hidden = YES;
    self.downloadProgress.hidden = YES;
    self.downloadProgress.progress = 0.0;
    [self.progressIndicator stopAnimating];
    
    // Remove all subviews from preview image view EXCEPT overlayView
    for (UIView *subview in self.previewImageView.subviews) {
        if (subview != self.overlayView) {
            [subview removeFromSuperview];
        }
    }
    
    // Reset selection border
    self.previewImageView.layer.borderColor = [UIColor clearColor].CGColor;
    self.previewImageView.layer.borderWidth = 0.0f;
    
    // Reset shadow
    self.previewImageView.layer.shadowOpacity = 0;
    
    // Reset background color
    self.previewImageView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
}
@end


// MARK: - VideoFilterController Implementation

@interface VideoFilterController () <NosmaiDelegate, NosmaiCameraDelegate, NosmaiEffectsDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>

// UI
@property(strong, nonatomic) UIView* previewContainerView;
@property(strong, nonatomic) UIButton* cameraSwitchButton;
@property(strong, nonatomic) UIButton* recordButton;
@property(strong, nonatomic) UIButton* clearFiltersButton;
// @property (strong, nonatomic) UICollectionView *filterCarouselView; // Removed horizontal carousel
@property (strong, nonatomic) UIButton *filtersButton;
@property (strong, nonatomic) UIButton *effectsButton;
@property (strong, nonatomic) UILabel *effectsLabel;
@property(strong, nonatomic) UIButton *gridButton;
@property(strong, nonatomic) UIButton *beautyButton;
@property (strong, nonatomic) UILabel *cameraSwitchLabel;
@property (strong, nonatomic) UILabel *filtersLabel;
@property (strong, nonatomic) UILabel *gridLabel;
@property (strong, nonatomic) UILabel *beautyLabel;
@property(strong, nonatomic) UIView *gridOverlayView;
@property (strong, nonatomic) UIView *bottomSheetView;
@property (strong, nonatomic) UIVisualEffectView *blurEffectView;
@property (strong, nonatomic) UICollectionView *bottomSheetCollectionView;
@property (strong, nonatomic) UIView *cloudFiltersLoadingView;
@property (strong, nonatomic) UIView *beautyBottomSheet;
@property (strong, nonatomic) UICollectionView *beautyFiltersCollectionView;
@property (strong, nonatomic) UIView *sliderContainerView;
@property (strong, nonatomic) UISlider *activeFilterSlider;
@property (strong, nonatomic) UILabel *sliderTitleLabel;
@property (strong, nonatomic) UILabel *sliderValueLabel;
@property (strong, nonatomic) NSArray<BeautyFilterModel *> *beautyFilters;
@property (strong, nonatomic) NSMutableDictionary<NSString *, BeautyFilterModel *> *activeBeautyFilters;
@property (strong, nonatomic) BeautyFilterModel *currentSliderFilter;

// State
@property(atomic, assign) BOOL isRecording;
@property(atomic, assign) BOOL isSDKReady;
@property (assign, nonatomic) BOOL areFiltersLoading;
@property (assign, nonatomic) BOOL isLoadingCloudFilters;
@property(assign, nonatomic) BOOL isGridVisible;
@property (strong, nonatomic) NSIndexPath *centeredIndexPath;
@property (strong, nonatomic) NSString *currentBottomSheetType;
@property (strong, nonatomic) NSString *currentAppliedFilterName; // Track currently applied filter
@property (strong, nonatomic) NSDictionary *currentAppliedEffectInfo; // Track currently applied effect info for preview

// Data
@property (strong, nonatomic) NSArray<NSDictionary *> *localFilters;
@property (strong, nonatomic) NSArray<NSDictionary *> *onlyFiltersArray;
@property (strong, nonatomic) NSArray<NSDictionary *> *onlyEffectsArray;
@property (strong, nonatomic) NSArray<NSDictionary *> *bottomSheetDataSource;
@property (strong, nonatomic) NSMutableDictionary *downloadingFilters;
@property (strong, nonatomic) UIImpactFeedbackGenerator *hapticGenerator;
@property (strong, nonatomic) NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters;

@property (strong, nonatomic) UIView *recordButtonOuterRing;
@property (strong, nonatomic) UIView *recordButtonInnerCircle;
@property (strong, nonatomic) CAShapeLayer *progressLayer;
@property (strong, nonatomic) UILabel *recordingTimeLabel;
@property (strong, nonatomic) NSTimer *recordingTimer;
@property (assign, nonatomic) NSTimeInterval recordingStartTime;


@property (strong, nonatomic) UIView *videoPreviewContainer;
@property (strong, nonatomic) UIImageView *videoThumbnailView;
@property (strong, nonatomic) UIButton *playButton;
@property (strong, nonatomic) NSURL *lastRecordedVideoURL;
@property (strong, nonatomic) AVPlayer *previewPlayer;
@property (strong, nonatomic) AVPlayerLayer *previewPlayerLayer;

@property (strong, nonatomic) UIView *fullScreenOverlay;
@property (strong, nonatomic) UIActivityIndicatorView *overlayLoadingIndicator;
@property (strong, nonatomic) UILabel *overlayLabel;

// Memory management
@property (strong, nonatomic) NSTimer *filterDebounceTimer;
@property (strong, nonatomic) NSIndexPath *pendingFilterIndexPath;
@property (assign, nonatomic) NSInteger rapidFilterChangeCount;
@property (strong, nonatomic) NSDate *lastFilterChangeTime;



@property (strong, nonatomic) NSString *currentActiveFilterPath;

// Method declarations
- (void)closeController;
- (void)updateFilterAsDownloaded:(NSString *)filterName withPath:(NSString *)path;

@end



@implementation VideoFilterController

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.areFiltersLoading = YES;
    self.isLoadingCloudFilters = YES; // Initially loading cloud filters
    self.downloadingFilters = [NSMutableDictionary dictionary];
    self.activeBeautyFilters = [NSMutableDictionary dictionary];
    
    // Initialize image cache if not already done
    if (!imageCache) {
        imageCache = [NSMutableDictionary dictionary];
    }
    self.currentAppliedFilterName = nil; // Initialize filter tracking
    self.currentAppliedEffectInfo = nil; // Initialize effect tracking
    [self setupBeautyFiltersData];
    [self setupUI];
    [self requestCameraAndMicPermissions];
    self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(resetAllBeautyFilterStates)
                                                 name:@"NosmaiSDKDidClearBuiltInFilters"
                                               object:nil];

}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isSDKReady) {
        // Reset preview container for smooth transition
        self.previewContainerView.alpha = 0.0;
        
        // 🔧 FIX: Re-establish preview view connection on appear
        [[NosmaiSDK sharedInstance] setPreviewView:_previewContainerView];
        [self startCameraCapture];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Smooth fade out transition when leaving camera view
    [UIView animateWithDuration:0.3 animations:^{
        self.previewContainerView.alpha = 0.0;
    }];
    
    [[NosmaiCore shared] cleanup];
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateCameraPreviewFrame];
    
    // Update grid lines whenever the view layout changes
    if (self.isGridVisible) {
        [self setupGridLines];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Don't handle touches that are on the bottom sheet collection view
    if ([touch.view isDescendantOfView:self.bottomSheetCollectionView]) {
        return NO;
    }
    
    // Don't handle touches that are on the beauty filters collection view
    if ([touch.view isDescendantOfView:self.beautyFiltersCollectionView]) {
        return NO;
    }
    
    // Don't handle touches on slider container
    if ([touch.view isDescendantOfView:self.sliderContainerView]) {
        return NO;
    }
    
    // Don't handle touches on any UIControl (buttons, etc.)
    if ([touch.view isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    return YES;
}

- (void)toggleGrid {
    [self animateButton:self.gridButton];

    self.isGridVisible = !self.isGridVisible;

    // Update grid button appearance to show active state
    self.gridButton.backgroundColor = self.isGridVisible ?
    [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.7] :
    [UIColor colorWithWhite:0.0 alpha:0.4];

    if (self.isGridVisible) {
        [self setupGridLines];
    }

    [UIView animateWithDuration:0.3 animations:^{
        self.gridOverlayView.hidden = !self.isGridVisible;
        self.gridOverlayView.alpha = self.isGridVisible ? 1.0 : 0.0;
    }];

}


#pragma mark - Memory Management

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    // Clear preview image cache in SDK
    [[NosmaiSDK sharedInstance] performSelector:@selector(didReceiveMemoryWarning:)
                                     withObject:nil];
    
    // Clear local caches
    [self handleMemoryWarning];
}

- (void)handleMemoryWarning {
    @autoreleasepool {
        // 1. Clear bottom sheet if not visible
        if (!self.bottomSheetView.superview) {
            self.bottomSheetDataSource = nil;
            [self.bottomSheetCollectionView reloadData];
        }
        
        // 2. Clear preview images from non-visible cells
        // Removed - filterCarouselView no longer exists
        
        // 3. Force garbage collection
        [[NosmaiSDK sharedInstance] performSelector:@selector(releaseUnusedResources)
                                         withObject:nil];
        

    }
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Register for memory warnings
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveMemoryWarning)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    
    // Update beauty button state when view appears in case license status changed
    [self updateBeautyButtonState];
}


- (void)resetAllBeautyFilterStates {
    dispatch_async(dispatch_get_main_queue(), ^{

        if (self.activeBeautyFilters.count == 0) {
            return;
        }

        for (BeautyFilterModel *filter in self.beautyFilters) {
            filter.isActive = NO;
            filter.currentValue = filter.defaultValue;
        }
        
        [self.activeBeautyFilters removeAllObjects];
                if (self.sliderContainerView && !self.sliderContainerView.hidden) {
            [self hideSlider];
        }
        
        if (self.beautyFiltersCollectionView) {
            [self.beautyFiltersCollectionView reloadData];
        }
    });
}




- (void)dealloc {
    
    // Stop any ongoing operations
    if (self.isRecording) {
        [[NosmaiCore shared] stopRecordingWithCompletion:nil];
    }
    
    // Invalidate timer
    [self.recordingTimer invalidate];
    self.recordingTimer = nil;
    
    // Clear all filter data
    [self cleanupFilterData];
    
    // Remove observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // 🔧 FIX: Stop SDK processing first to avoid circular dependency
    [[NosmaiSDK sharedInstance] stopProcessing];
    
    // Stop camera if running
    if ([NosmaiCore shared].camera.isCapturing) {
        [[NosmaiCore shared].camera stopCapture];
    }
    
    // 🔧 FIX: Don't call cleanup in dealloc - it's already done in viewWillDisappear
    // The SDK singleton should persist for reuse
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"NosmaiSDKDidClearBuiltInFilters" object:nil];

}

#pragma mark - Permissions

- (void)requestCameraAndMicPermissions {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL audioGranted) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (!audioGranted) {
                            [self showPermissionAlert:@"Microphone" isRequired:NO];
                        }
                        [self setupNosmaiCore];
                    });
                }];
            } else {
                [self showPermissionAlert:@"Camera" isRequired:YES];
            }
        });
    }];
}

- (void)showPermissionAlert:(NSString *)permission isRequired:(BOOL)isRequired {
    NSString *title = [NSString stringWithFormat:@"%@ Access Denied", permission];
    NSString *message = [NSString stringWithFormat:@"%@ access is required for this app to function. Please enable it in Settings.", permission];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (isRequired) { [self closeController]; }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark - UI Setup

- (void)setupUI {
    _previewContainerView = [[UIView alloc] init];
    _previewContainerView.backgroundColor = UIColor.blackColor;
    _previewContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewContainerView.alpha = 0.0; // Start with transparent for smooth transition
    [self.view addSubview:_previewContainerView];
    
    // Clear filters button - using the helper method
    _clearFiltersButton = [self createButtonWithImageNamed:@"xmark" action:@selector(clearAllFilters)];
    
    // Camera switch button - CUSTOM CREATION (don't use createButtonWithImageNamed)
    _cameraSwitchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cameraSwitchButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    _cameraSwitchButton.layer.cornerRadius = kDefaultButtonSize / 2.0;
    _cameraSwitchButton.tintColor = UIColor.whiteColor;
    
    // Use camera.rotate icon with custom configuration
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIImage *cameraIcon = [UIImage systemImageNamed:@"camera.rotate" withConfiguration:config];
    
    // If camera.rotate is not available (older iOS), fallback to arrow.clockwise
    if (!cameraIcon) {
        cameraIcon = [UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:config];
    }
    
    [_cameraSwitchButton setImage:cameraIcon forState:UIControlStateNormal];
    [_cameraSwitchButton addTarget:self action:@selector(switchCamera) forControlEvents:UIControlEventTouchUpInside];
    _cameraSwitchButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow for professional depth
    _cameraSwitchButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _cameraSwitchButton.layer.shadowOffset = CGSizeMake(0, 2);
    _cameraSwitchButton.layer.shadowOpacity = 0.3;
    _cameraSwitchButton.layer.shadowRadius = 4;
    
    // Other buttons - using the helper method
    _filtersButton = [self createButtonWithImageNamed:@"wand.and.stars.inverse" action:@selector(handleFiltersButtonPress)];
    _gridButton = [self createButtonWithImageNamed:@"grid" action:@selector(toggleGrid)];
    _beautyButton = [self createButtonWithImageNamed:@"face.smiling" action:@selector(handleBeautyButtonPress)];
    
    // Effects button - CUSTOM CREATION with box shape
    _effectsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _effectsButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    _effectsButton.layer.cornerRadius = 8.0; // Box shape with rounded corners
    _effectsButton.layer.borderWidth = 1.5; // White border
    _effectsButton.layer.borderColor = [UIColor whiteColor].CGColor; // White border color
    _effectsButton.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *effectsConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [_effectsButton setImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:effectsConfig] forState:UIControlStateNormal];
    [_effectsButton addTarget:self action:@selector(handleEffectsButtonPress) forControlEvents:UIControlEventTouchUpInside];
    _effectsButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow for depth
    _effectsButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _effectsButton.layer.shadowOffset = CGSizeMake(0, 2);
    _effectsButton.layer.shadowOpacity = 0.3;
    _effectsButton.layer.shadowRadius = 4;

    // Create Effects Label
    _effectsLabel = [[UILabel alloc] init];
    _effectsLabel.text = @"Effects";
    _effectsLabel.textColor = [UIColor whiteColor];
    _effectsLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _effectsLabel.textAlignment = NSTextAlignmentCenter;
    _effectsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow to label for better visibility
    _effectsLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _effectsLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _effectsLabel.layer.shadowOpacity = 0.5;
    _effectsLabel.layer.shadowRadius = 2;
    
    // Create Camera Switch Label
    _cameraSwitchLabel = [[UILabel alloc] init];
    _cameraSwitchLabel.text = @"Camera";
    _cameraSwitchLabel.textColor = [UIColor whiteColor];
    _cameraSwitchLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _cameraSwitchLabel.textAlignment = NSTextAlignmentCenter;
    _cameraSwitchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _cameraSwitchLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _cameraSwitchLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _cameraSwitchLabel.layer.shadowOpacity = 0.5;
    _cameraSwitchLabel.layer.shadowRadius = 2;
    
    // Create Filters Label
    _filtersLabel = [[UILabel alloc] init];
    _filtersLabel.text = @"Filters";
    _filtersLabel.textColor = [UIColor whiteColor];
    _filtersLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _filtersLabel.textAlignment = NSTextAlignmentCenter;
    _filtersLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _filtersLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _filtersLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _filtersLabel.layer.shadowOpacity = 0.5;
    _filtersLabel.layer.shadowRadius = 2;
    
    // Create Grid Label
    _gridLabel = [[UILabel alloc] init];
    _gridLabel.text = @"Grid";
    _gridLabel.textColor = [UIColor whiteColor];
    _gridLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _gridLabel.textAlignment = NSTextAlignmentCenter;
    _gridLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _gridLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _gridLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _gridLabel.layer.shadowOpacity = 0.5;
    _gridLabel.layer.shadowRadius = 2;
    
    // Create Beauty Label
    _beautyLabel = [[UILabel alloc] init];
    _beautyLabel.text = @"Beauty";
    _beautyLabel.textColor = [UIColor whiteColor];
    _beautyLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _beautyLabel.textAlignment = NSTextAlignmentCenter;
    _beautyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _beautyLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _beautyLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _beautyLabel.layer.shadowOpacity = 0.5;
    _beautyLabel.layer.shadowRadius = 2;
    
    // Add all buttons and labels to view
    [self.view addSubview:_clearFiltersButton];
    [self.view addSubview:_cameraSwitchButton];
    [self.view addSubview:_cameraSwitchLabel];
    [self.view addSubview:_filtersButton];
    [self.view addSubview:_filtersLabel];
    [self.view addSubview:_effectsButton];
    [self.view addSubview:_effectsLabel];
    [self.view addSubview:_gridButton];
    [self.view addSubview:_gridLabel];
    [self.view addSubview:_beautyButton];
    [self.view addSubview:_beautyLabel];
    
    _gridOverlayView = [[UIView alloc] init];
    _gridOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    _gridOverlayView.userInteractionEnabled = NO;
    _gridOverlayView.hidden = YES;
    [self.view addSubview:_gridOverlayView];
    
    // Call new setup method for record button
    [self setupRecordButton];
    
    [self setupVideoPreviewBox];
    [self setupConstraints];
    [self setupGridLines];
}


- (void)showFullScreenLoader {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Create overlay if it doesn't exist
        if (!self.fullScreenOverlay) {
            // Create full screen overlay
            self.fullScreenOverlay = [[UIView alloc] init];
            self.fullScreenOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
            self.fullScreenOverlay.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:self.fullScreenOverlay];
            
            // Create native iOS loading indicator
            self.overlayLoadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            self.overlayLoadingIndicator.color = [UIColor whiteColor];
            self.overlayLoadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
            [self.fullScreenOverlay addSubview:self.overlayLoadingIndicator];
            
            // Create overlay label with professional styling
            self.overlayLabel = [[UILabel alloc] init];
            self.overlayLabel.text = @"Processing Video";
            self.overlayLabel.textColor = [UIColor whiteColor];
            self.overlayLabel.font = [UIFont systemFontOfSize:16.0f weight:UIFontWeightRegular];
            self.overlayLabel.textAlignment = NSTextAlignmentCenter;
            self.overlayLabel.translatesAutoresizingMaskIntoConstraints = NO;
            self.overlayLabel.alpha = 0.9;
            
            // Add shadow for better readability
            self.overlayLabel.layer.shadowColor = [UIColor blackColor].CGColor;
            self.overlayLabel.layer.shadowOffset = CGSizeMake(0, 1);
            self.overlayLabel.layer.shadowOpacity = 0.3;
            self.overlayLabel.layer.shadowRadius = 2;
            
            [self.fullScreenOverlay addSubview:self.overlayLabel];
            
            // Setup constraints
            [NSLayoutConstraint activateConstraints:@[
                // Overlay fills entire view
                [self.fullScreenOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                [self.fullScreenOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [self.fullScreenOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                [self.fullScreenOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
                
                // Loading indicator centered in overlay
                [self.overlayLoadingIndicator.centerXAnchor constraintEqualToAnchor:self.fullScreenOverlay.centerXAnchor],
                [self.overlayLoadingIndicator.centerYAnchor constraintEqualToAnchor:self.fullScreenOverlay.centerYAnchor],
                
                // Label below loading indicator with more spacing
                [self.overlayLabel.centerXAnchor constraintEqualToAnchor:self.fullScreenOverlay.centerXAnchor],
                [self.overlayLabel.topAnchor constraintEqualToAnchor:self.overlayLoadingIndicator.bottomAnchor constant:20.0f]
            ]];
        }
        
        // Show overlay with animation
        self.fullScreenOverlay.alpha = 0.0f;
        [self.overlayLoadingIndicator startAnimating];
        
        [UIView animateWithDuration:0.3 animations:^{
            self.fullScreenOverlay.alpha = 1.0f;
        }];
    });
}



- (void)hideFullScreenLoader {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.fullScreenOverlay) {
            [UIView animateWithDuration:0.3 animations:^{
                self.fullScreenOverlay.alpha = 0.0f;
            } completion:^(BOOL finished) {
                [self.overlayLoadingIndicator stopAnimating];
                [self.fullScreenOverlay removeFromSuperview];
                self.fullScreenOverlay = nil;
                self.overlayLoadingIndicator = nil;
                self.overlayLabel = nil;
            }];
        }
    });
}




- (void)setupVideoPreviewBox {
    self.videoPreviewContainer = [[UIView alloc] init];
    self.videoPreviewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.videoPreviewContainer.backgroundColor = [UIColor blackColor];
    self.videoPreviewContainer.layer.cornerRadius = 8;
    self.videoPreviewContainer.clipsToBounds = YES;
    self.videoPreviewContainer.hidden = YES;
    self.videoPreviewContainer.alpha = 0;
    
    self.videoPreviewContainer.layer.borderWidth = 1.5;
    self.videoPreviewContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    
    // Thumbnail image view
    self.videoThumbnailView = [[UIImageView alloc] init];
    self.videoThumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.videoThumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.videoThumbnailView.clipsToBounds = YES;
    [self.videoPreviewContainer addSubview:self.videoThumbnailView];
    
    // Play button overlay - smaller and more subtle
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.playButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    self.playButton.layer.cornerRadius = 15;
    
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    UIImage *playIcon = [UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig];
    [self.playButton setImage:playIcon forState:UIControlStateNormal];
    self.playButton.tintColor = [UIColor whiteColor];
    
    [self.playButton addTarget:self action:@selector(playPreviewVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.videoPreviewContainer addSubview:self.playButton];
    
    // Add tap gesture to the whole container
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playPreviewVideo)];
    [self.videoPreviewContainer addGestureRecognizer:tapGesture];
    
    [self.view addSubview:self.videoPreviewContainer];
    
    [NSLayoutConstraint activateConstraints:@[
        // Container constraints - positioned to the right of record button
        [self.videoPreviewContainer.centerYAnchor constraintEqualToAnchor:self.recordButton.centerYAnchor],
        [self.videoPreviewContainer.leadingAnchor constraintEqualToAnchor:self.recordButton.trailingAnchor constant:50],
        [self.videoPreviewContainer.widthAnchor constraintEqualToConstant:50],
        [self.videoPreviewContainer.heightAnchor constraintEqualToConstant:50],
        
        // Thumbnail fills container
        [self.videoThumbnailView.topAnchor constraintEqualToAnchor:self.videoPreviewContainer.topAnchor],
        [self.videoThumbnailView.leadingAnchor constraintEqualToAnchor:self.videoPreviewContainer.leadingAnchor],
        [self.videoThumbnailView.trailingAnchor constraintEqualToAnchor:self.videoPreviewContainer.trailingAnchor],
        [self.videoThumbnailView.bottomAnchor constraintEqualToAnchor:self.videoPreviewContainer.bottomAnchor],
        
        // Play button centered and smaller
        [self.playButton.centerXAnchor constraintEqualToAnchor:self.videoPreviewContainer.centerXAnchor],
        [self.playButton.centerYAnchor constraintEqualToAnchor:self.videoPreviewContainer.centerYAnchor],
        [self.playButton.widthAnchor constraintEqualToConstant:30],
        [self.playButton.heightAnchor constraintEqualToConstant:30],
    ]];
}


// ============================================
// STEP 3: Add this NEW method after setupUI
// ============================================
- (void)setupRecordButton {
    // Outer container for the record button
    _recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _recordButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_recordButton addTarget:self action:@selector(recordButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_recordButton];
    
    // Outer ring (will show progress/pulse)
    _recordButtonOuterRing = [[UIView alloc] init];
    _recordButtonOuterRing.translatesAutoresizingMaskIntoConstraints = NO;
    _recordButtonOuterRing.backgroundColor = [UIColor clearColor];
    _recordButtonOuterRing.layer.borderColor = [UIColor whiteColor].CGColor;
    _recordButtonOuterRing.layer.borderWidth = 4.0;
    _recordButtonOuterRing.layer.cornerRadius = 40;
    _recordButtonOuterRing.userInteractionEnabled = NO;
    [_recordButton addSubview:_recordButtonOuterRing];
    
    // Progress layer for recording
    _progressLayer = [CAShapeLayer layer];
    _progressLayer.fillColor = [UIColor clearColor].CGColor;
    _progressLayer.strokeColor = [UIColor redColor].CGColor;
    _progressLayer.lineWidth = 4.0;
    _progressLayer.strokeEnd = 0.0;
    _progressLayer.lineCap = kCALineCapRound;
    
    // Inner circle/square
    _recordButtonInnerCircle = [[UIView alloc] init];
    _recordButtonInnerCircle.translatesAutoresizingMaskIntoConstraints = NO;
    _recordButtonInnerCircle.backgroundColor = [UIColor redColor];
    _recordButtonInnerCircle.layer.cornerRadius = 30;
    _recordButtonInnerCircle.userInteractionEnabled = NO;
    [_recordButton addSubview:_recordButtonInnerCircle];
    
    // Recording time label
    _recordingTimeLabel = [[UILabel alloc] init];
    _recordingTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _recordingTimeLabel.text = @"00:00";
    _recordingTimeLabel.textColor = [UIColor whiteColor];
    _recordingTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    _recordingTimeLabel.textAlignment = NSTextAlignmentCenter;
    _recordingTimeLabel.hidden = YES;
    _recordingTimeLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    _recordingTimeLabel.layer.shadowOffset = CGSizeMake(0, 1);
    _recordingTimeLabel.layer.shadowOpacity = 0.5;
    _recordingTimeLabel.layer.shadowRadius = 2;
    [self.view addSubview:_recordingTimeLabel];
}


- (UIButton *)createButtonWithImageNamed:(NSString *)imageName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    button.layer.cornerRadius = kDefaultButtonSize / 2.0;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    [button setImage:[UIImage systemImageNamed:imageName withConfiguration:config] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)setupConstraints {
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_previewContainerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_previewContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_previewContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_previewContainerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [_cameraSwitchButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:kDefaultMargin],
        [_cameraSwitchButton.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-kDefaultMargin],
        [_cameraSwitchButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_cameraSwitchButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        // Camera Switch Label constraints
        [_cameraSwitchLabel.topAnchor constraintEqualToAnchor:_cameraSwitchButton.bottomAnchor constant:3],
        [_cameraSwitchLabel.centerXAnchor constraintEqualToAnchor:_cameraSwitchButton.centerXAnchor],
        [_cameraSwitchLabel.widthAnchor constraintEqualToConstant:60],
        
        // CHANGED: Updated record button constraints
        [_recordButton.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-20],
        [_recordButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_recordButton.widthAnchor constraintEqualToConstant:80],
        [_recordButton.heightAnchor constraintEqualToConstant:80],
        
        // NEW: Outer ring constraints
        [_recordButtonOuterRing.centerXAnchor constraintEqualToAnchor:_recordButton.centerXAnchor],
        [_recordButtonOuterRing.centerYAnchor constraintEqualToAnchor:_recordButton.centerYAnchor],
        [_recordButtonOuterRing.widthAnchor constraintEqualToConstant:80],
        [_recordButtonOuterRing.heightAnchor constraintEqualToConstant:80],
        
        // NEW: Inner circle constraints
        [_recordButtonInnerCircle.centerXAnchor constraintEqualToAnchor:_recordButton.centerXAnchor],
        [_recordButtonInnerCircle.centerYAnchor constraintEqualToAnchor:_recordButton.centerYAnchor],
        [_recordButtonInnerCircle.widthAnchor constraintEqualToConstant:60],
        [_recordButtonInnerCircle.heightAnchor constraintEqualToConstant:60],
        
        // NEW: Time label constraints
        [_recordingTimeLabel.bottomAnchor constraintEqualToAnchor:_recordButton.topAnchor constant:-15],
        [_recordingTimeLabel.centerXAnchor constraintEqualToAnchor:_recordButton.centerXAnchor],
        
        // Move clearFiltersButton to top left
        [_clearFiltersButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:kDefaultMargin],
        [_clearFiltersButton.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:kDefaultMargin],
        [_clearFiltersButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_clearFiltersButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        [_filtersButton.topAnchor constraintEqualToAnchor:_cameraSwitchLabel.bottomAnchor constant:18],
        [_filtersButton.centerXAnchor constraintEqualToAnchor:_cameraSwitchButton.centerXAnchor],
        [_filtersButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_filtersButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        // Filters Label constraints
        [_filtersLabel.topAnchor constraintEqualToAnchor:_filtersButton.bottomAnchor constant:3],
        [_filtersLabel.centerXAnchor constraintEqualToAnchor:_filtersButton.centerXAnchor],
        [_filtersLabel.widthAnchor constraintEqualToConstant:60],
        
        // Move effectsButton to where clearFiltersButton was (near record button)
        [_effectsButton.centerYAnchor constraintEqualToAnchor:_recordButton.centerYAnchor constant:-8], // Slightly up to make room for label
        [_effectsButton.trailingAnchor constraintEqualToAnchor:_recordButton.leadingAnchor constant:-50],
        [_effectsButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_effectsButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        // Effects Label constraints
        [_effectsLabel.topAnchor constraintEqualToAnchor:_effectsButton.bottomAnchor constant:3],
        [_effectsLabel.centerXAnchor constraintEqualToAnchor:_effectsButton.centerXAnchor],
        [_effectsLabel.widthAnchor constraintEqualToConstant:60],
        
        [_gridButton.topAnchor constraintEqualToAnchor:_filtersLabel.bottomAnchor constant:18],
        [_gridButton.centerXAnchor constraintEqualToAnchor:_filtersButton.centerXAnchor],
        [_gridButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_gridButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        // Grid Label constraints
        [_gridLabel.topAnchor constraintEqualToAnchor:_gridButton.bottomAnchor constant:3],
        [_gridLabel.centerXAnchor constraintEqualToAnchor:_gridButton.centerXAnchor],
        [_gridLabel.widthAnchor constraintEqualToConstant:60],
        
        [_beautyButton.topAnchor constraintEqualToAnchor:_gridLabel.bottomAnchor constant:18],
        [_beautyButton.centerXAnchor constraintEqualToAnchor:_gridButton.centerXAnchor],
        [_beautyButton.widthAnchor constraintEqualToConstant:kDefaultButtonSize],
        [_beautyButton.heightAnchor constraintEqualToConstant:kDefaultButtonSize],
        
        // Beauty Label constraints
        [_beautyLabel.topAnchor constraintEqualToAnchor:_beautyButton.bottomAnchor constant:3],
        [_beautyLabel.centerXAnchor constraintEqualToAnchor:_beautyButton.centerXAnchor],
        [_beautyLabel.widthAnchor constraintEqualToConstant:60],
        
        // Ensure beauty label has proper bottom spacing
        [_beautyLabel.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-80],
        
        
        [_gridOverlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_gridOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_gridOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_gridOverlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

// Method to update effects button with preview
- (void)updateEffectsButtonWithEffect:(NSDictionary *)effectInfo {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!effectInfo) {
            // Reset to default sparkles icon
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
            [self.effectsButton setImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:config] forState:UIControlStateNormal];
            [self.effectsButton setBackgroundImage:nil forState:UIControlStateNormal];
            self.effectsButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
            return;
        }
        
        NSString *effectName = effectInfo[@"name"] ?: effectInfo[@"displayName"];
        
        // Load effect preview image
        NSString *previewPath = effectInfo[@"previewPath"];
        if (previewPath && previewPath.length > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                @autoreleasepool {
                    UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:previewPath];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (previewImage) {
                            // Remove icon and set preview image as background
                            [self.effectsButton setImage:nil forState:UIControlStateNormal];
                            
                            // Create rounded background image
                            UIImage *roundedImage = [self roundedImageFromImage:previewImage cornerRadius:8.0 size:CGSizeMake(kDefaultButtonSize, kDefaultButtonSize)];
                            [self.effectsButton setBackgroundImage:roundedImage forState:UIControlStateNormal];
                            self.effectsButton.backgroundColor = [UIColor clearColor];
                        } else {
                            // Fallback to sparkles icon if preview not available
                            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
                            [self.effectsButton setImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:config] forState:UIControlStateNormal];
                            [self.effectsButton setBackgroundImage:nil forState:UIControlStateNormal];
                            self.effectsButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
                        }
                    });
                }
            });
        } else {
            // No preview path available, use sparkles icon
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
            [self.effectsButton setImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:config] forState:UIControlStateNormal];
            [self.effectsButton setBackgroundImage:nil forState:UIControlStateNormal];
            self.effectsButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        }
    });
}

// Helper method to create rounded image
- (UIImage *)roundedImageFromImage:(UIImage *)image cornerRadius:(CGFloat)cornerRadius size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:cornerRadius];
    CGContextAddPath(context, path.CGPath);
    CGContextClip(context);
    
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    
    UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return roundedImage;
}

// Method to show download started toast
- (void)showDownloadStartedToastForFilter:(NSString *)filterName {
    // Remove any existing toast
    UIView *existingToast = [self.view viewWithTag:888];
    if (existingToast) {
        [existingToast removeFromSuperview];
    }
    
    // Create toast view
    UIView *toastView = [[UIView alloc] init];
    toastView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    toastView.layer.cornerRadius = 20;
    toastView.translatesAutoresizingMaskIntoConstraints = NO;
    toastView.tag = 888;
    
    // Add download icon
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]];
    iconView.tintColor = [UIColor systemBlueColor];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [toastView addSubview:iconView];
    
    // Add label
    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"Downloading %@...", filterName];
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toastView addSubview:label];
    
    [self.view addSubview:toastView];
    
    // Set constraints
    [NSLayoutConstraint activateConstraints:@[
        [toastView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toastView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [toastView.heightAnchor constraintEqualToConstant:40],
        
        [iconView.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
        [iconView.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:20],
        [iconView.heightAnchor constraintEqualToConstant:20],
        
        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:toastView.trailingAnchor constant:-15],
        [label.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
    ]];
    
    // Animate in
    toastView.alpha = 0;
    toastView.transform = CGAffineTransformMakeTranslation(0, -20);
    [UIView animateWithDuration:0.3 animations:^{
        toastView.alpha = 1;
        toastView.transform = CGAffineTransformIdentity;
    }];
}

// Method to show download completed toast
- (void)showDownloadCompletedToastForFilter:(NSString *)filterName success:(BOOL)success {
    // Remove existing toast
    UIView *existingToast = [self.view viewWithTag:888];
    if (existingToast) {
        [UIView animateWithDuration:0.2 animations:^{
            existingToast.alpha = 0;
        } completion:^(BOOL finished) {
            [existingToast removeFromSuperview];
            [self createCompletionToast:filterName success:success];
        }];
    } else {
        [self createCompletionToast:filterName success:success];
    }
}

- (void)createCompletionToast:(NSString *)filterName success:(BOOL)success {
    // Create toast view
    UIView *toastView = [[UIView alloc] init];
    toastView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    toastView.layer.cornerRadius = 20;
    toastView.translatesAutoresizingMaskIntoConstraints = NO;
    toastView.tag = 889;
    
    // Add icon
    NSString *iconName = success ? @"checkmark.circle" : @"xmark.circle";
    UIColor *iconColor = success ? [UIColor systemGreenColor] : [UIColor systemRedColor];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iconView.tintColor = iconColor;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [toastView addSubview:iconView];
    
    // Add label
    UILabel *label = [[UILabel alloc] init];
    if (success) {
        label.text = [NSString stringWithFormat:@"%@ downloaded!", filterName];
    } else {
        label.text = [NSString stringWithFormat:@"Failed to download %@", filterName];
    }
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toastView addSubview:label];
    
    [self.view addSubview:toastView];
    
    // Set constraints
    [NSLayoutConstraint activateConstraints:@[
        [toastView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toastView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [toastView.heightAnchor constraintEqualToConstant:40],
        
        [iconView.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
        [iconView.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:20],
        [iconView.heightAnchor constraintEqualToConstant:20],
        
        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:toastView.trailingAnchor constant:-15],
        [label.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
    ]];
    
    // Animate in
    toastView.alpha = 0;
    toastView.transform = CGAffineTransformMakeTranslation(0, -20);
    [UIView animateWithDuration:0.3 animations:^{
        toastView.alpha = 1;
        toastView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // Auto-dismiss after delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastView.alpha = 0;
                toastView.transform = CGAffineTransformMakeTranslation(0, -20);
            } completion:^(BOOL finished) {
                [toastView removeFromSuperview];
            }];
        });
    }];
}

- (void)setupBeautyFiltersData {
    NSMutableArray *filters = [NSMutableArray array];
    
    // Face Beautification filters
    BeautyFilterModel *skinSmoothing = [[BeautyFilterModel alloc] init];
    skinSmoothing.identifier = @"skin_smoothing";
    skinSmoothing.displayName = @"Smooth\nSkin";
    skinSmoothing.iconName = @"face.smiling";
    skinSmoothing.category = @"Beauty";
    skinSmoothing.type = BeautyFilterTypeSlider;
    skinSmoothing.minValue = 0.0;
    skinSmoothing.maxValue = 10.0;
    skinSmoothing.defaultValue = 0.0;
    skinSmoothing.currentValue = 0.0;
    skinSmoothing.methodName = @"applySkinSmoothing:";
    [filters addObject:skinSmoothing];
    
    BeautyFilterModel *skinWhitening = [[BeautyFilterModel alloc] init];
    skinWhitening.identifier = @"skin_whitening";
    skinWhitening.displayName = @"Brighten\nSkin";
    skinWhitening.iconName = @"sun.max";
    skinWhitening.category = @"Beauty";
    skinWhitening.type = BeautyFilterTypeSlider;
    skinWhitening.minValue = 0.0;
    skinWhitening.maxValue = 10.0;
    skinWhitening.defaultValue = 0.0;
    skinWhitening.currentValue = 0.0;
    skinWhitening.methodName = @"applySkinWhitening:";
    [filters addObject:skinWhitening];
    
    BeautyFilterModel *faceSlimming = [[BeautyFilterModel alloc] init];
    faceSlimming.identifier = @"face_slimming";
    faceSlimming.displayName = @"Slim\nFace";
    faceSlimming.iconName = @"arrow.left.and.right";
    faceSlimming.category = @"Beauty";
    faceSlimming.type = BeautyFilterTypeSlider;
    faceSlimming.minValue = 0.0;
    faceSlimming.maxValue = 10.0;
    faceSlimming.defaultValue = 0.0;
    faceSlimming.currentValue = 0.0;
    faceSlimming.methodName = @"applyFaceSlimming:";
    [filters addObject:faceSlimming];
    
    BeautyFilterModel *eyeEnlargement = [[BeautyFilterModel alloc] init];
    eyeEnlargement.identifier = @"eye_enlargement";
    eyeEnlargement.displayName = @"Enlarge\nEyes";
    eyeEnlargement.iconName = @"eye";
    eyeEnlargement.category = @"Beauty";
    eyeEnlargement.type = BeautyFilterTypeSlider;
    eyeEnlargement.minValue = 0.0;
    eyeEnlargement.maxValue = 10.0;
    eyeEnlargement.defaultValue = 0.0;
    eyeEnlargement.currentValue = 0.0;
    eyeEnlargement.methodName = @"applyEyeEnlargement:";
    [filters addObject:eyeEnlargement];
    
    BeautyFilterModel *noseSize = [[BeautyFilterModel alloc] init];
    noseSize.identifier = @"nose_size";
    noseSize.displayName = @"Nose\nSize";
    noseSize.iconName = @"triangle";
    noseSize.category = @"Beauty";
    noseSize.type = BeautyFilterTypeSlider;
    noseSize.minValue = 0.0;
    noseSize.maxValue = 100.0;
    noseSize.defaultValue = 50.0;
    noseSize.currentValue = 50.0;
    noseSize.methodName = @"applyNoseSize:";
    [filters addObject:noseSize];
    
    BeautyFilterModel *lipstick = [[BeautyFilterModel alloc] init];
    lipstick.identifier = @"lipstick";
    lipstick.displayName = @"Lipstick";
    lipstick.iconName = @"mouth";
    lipstick.category = @"Makeup";
    lipstick.type = BeautyFilterTypeSlider;
    lipstick.minValue = 0.0;
    lipstick.maxValue = 10.0;
    lipstick.defaultValue = 0.0;
    lipstick.currentValue = 0.0;
    lipstick.methodName = @"applyMakeupBlendLevel:level:";
    [filters addObject:lipstick];
    
    BeautyFilterModel *blusher = [[BeautyFilterModel alloc] init];
    blusher.identifier = @"blusher";
    blusher.displayName = @"Blush";
    blusher.iconName = @"paintpalette";
    blusher.category = @"Makeup";
    blusher.type = BeautyFilterTypeSlider;
    blusher.minValue = 0.0;
    blusher.maxValue = 50.0;
    blusher.defaultValue = 0.0;
    blusher.currentValue = 0.0;
    blusher.methodName = @"applyMakeupBlendLevel:level:";
    [filters addObject:blusher];
    
    // Color & Tone Adjustments
    BeautyFilterModel *brightness = [[BeautyFilterModel alloc] init];
    brightness.identifier = @"brightness";
    brightness.displayName = @"Brightness";
    brightness.iconName = @"sun.min";
    brightness.category = @"Adjust";
    brightness.type = BeautyFilterTypeSlider;
    brightness.minValue = -0.5f;
    brightness.maxValue = 0.5f;
    brightness.defaultValue = 0.0;
    brightness.currentValue = 0.0;
    brightness.methodName = @"applyBrightnessFilter:";
    [filters addObject:brightness];
    
    BeautyFilterModel *contrast = [[BeautyFilterModel alloc] init];
    contrast.identifier = @"contrast";
    contrast.displayName = @"Contrast";
    contrast.iconName = @"circle.lefthalf.filled";
    contrast.category = @"Adjust";
    contrast.type = BeautyFilterTypeSlider;
    contrast.minValue = 1.0f;
    contrast.maxValue = 4.0;
    contrast.defaultValue = 1.0;
    contrast.currentValue = 1.0;
    contrast.methodName = @"applyContrastFilter:";
    [filters addObject:contrast];
    
    BeautyFilterModel *hue = [[BeautyFilterModel alloc] init];
    hue.identifier = @"hue";
    hue.displayName = @"Hue";
    hue.iconName = @"paintbrush";
    hue.category = @"Adjust";
    hue.type = BeautyFilterTypeSlider;
    hue.minValue = 0.0;
    hue.maxValue = 360.0;
    hue.defaultValue = 0.0;
    hue.currentValue = 0.0;
    hue.methodName = @"applyHue:";
    [filters addObject:hue];
    
  
    
    // Simple toggles
    BeautyFilterModel *grayscale = [[BeautyFilterModel alloc] init];
    grayscale.identifier = @"grayscale";
    grayscale.displayName = @"B&W";
    grayscale.iconName = @"circle.fill";
    grayscale.category = @"Effects";
    grayscale.type = BeautyFilterTypeToggle;
    grayscale.methodName = @"applyGrayscaleFilter";
    [filters addObject:grayscale];
    
    
    // HSB Adjustment (using adjustHSBWithHue - simplified to Saturation since Hue is already included)
    BeautyFilterModel *saturation = [[BeautyFilterModel alloc] init];
    saturation.identifier = @"saturation";
    saturation.displayName = @"Saturation";
    saturation.iconName = @"drop.fill";
    saturation.category = @"Adjust";
    saturation.type = BeautyFilterTypeSlider;
    saturation.minValue = 0.0;
    saturation.maxValue = 2.0;
    saturation.defaultValue = 1.0;
    saturation.currentValue = 1.0;
    saturation.methodName = @"adjustHSBWithHue:saturation:brightness:";
    [filters addObject:saturation];
    
    // White Balance Temperature
    BeautyFilterModel *temperature = [[BeautyFilterModel alloc] init];
    temperature.identifier = @"temperature";
    temperature.displayName = @"Temp";
    temperature.iconName = @"thermometer";
    temperature.category = @"Adjust";
    temperature.type = BeautyFilterTypeSlider;
    temperature.minValue = 2000.0;
    temperature.maxValue = 8000.0;
    temperature.defaultValue = 5000.0;
    temperature.currentValue = 5000.0;
    temperature.methodName = @"applyWhiteBalanceWithTemperature:tint:";
    [filters addObject:temperature];
    
    // RGB Red Channel
    BeautyFilterModel *redChannel = [[BeautyFilterModel alloc] init];
    redChannel.identifier = @"red_channel";
    redChannel.displayName = @"Red";
    redChannel.iconName = @"r.circle.fill";
    redChannel.category = @"Adjust";
    redChannel.type = BeautyFilterTypeSlider;
    redChannel.minValue = 0.0;
    redChannel.maxValue = 2.0;
    redChannel.defaultValue = 1.0;
    redChannel.currentValue = 1.0;
    redChannel.methodName = @"applyRGBFilterWithRed:green:blue:";
    [filters addObject:redChannel];
    
    // RGB Green Channel
    BeautyFilterModel *greenChannel = [[BeautyFilterModel alloc] init];
    greenChannel.identifier = @"green_channel";
    greenChannel.displayName = @"Green";
    greenChannel.iconName = @"g.circle.fill";
    greenChannel.category = @"Adjust";
    greenChannel.type = BeautyFilterTypeSlider;
    greenChannel.minValue = 0.0;
    greenChannel.maxValue = 2.0;
    greenChannel.defaultValue = 1.0;
    greenChannel.currentValue = 1.0;
    greenChannel.methodName = @"applyRGBFilterWithRed:green:blue:";
    [filters addObject:greenChannel];
    
    // RGB Blue Channel
    BeautyFilterModel *blueChannel = [[BeautyFilterModel alloc] init];
    blueChannel.identifier = @"blue_channel";
    blueChannel.displayName = @"Blue";
    blueChannel.iconName = @"b.circle.fill";
    blueChannel.category = @"Adjust";
    blueChannel.type = BeautyFilterTypeSlider;
    blueChannel.minValue = 0.0;
    blueChannel.maxValue = 2.0;
    blueChannel.defaultValue = 1.0;
    blueChannel.currentValue = 1.0;
    blueChannel.methodName = @"applyRGBFilterWithRed:green:blue:";
    [filters addObject:blueChannel];
    
    
    // Crosshatch Filter
    BeautyFilterModel *sharpening = [[BeautyFilterModel alloc] init];
    sharpening.identifier = @"sharpening";
    sharpening.displayName = @"Sharpen";
    sharpening.iconName = @"circle.grid.cross";
    sharpening.category = @"Beauty";
    sharpening.type = BeautyFilterTypeSlider;
    sharpening.minValue = 0.0;
    sharpening.maxValue = 10.0;
    sharpening.defaultValue = 0.0;
    sharpening.currentValue = 0.0;
    sharpening.methodName = @"applySharpening:";
    [filters addObject:sharpening];
    
    self.beautyFilters = [filters copy];
}

- (void)setupGridLines {
    // Clear any existing lines
    for (UIView *subview in self.gridOverlayView.subviews) {
        [subview removeFromSuperview];
    }
    
    // Create the lines for the 3x3 grid
    CGFloat lineWidth = 1.0;
    UIColor *lineColor = [UIColor colorWithWhite:1.0 alpha:0.7]; // White semi-transparent
    
    // We'll create 4 lines (2 horizontal, 2 vertical) to make a 3x3 grid
    for (int i = 0; i < 4; i++) {
        UIView *lineView = [[UIView alloc] init];
        lineView.backgroundColor = lineColor;
        lineView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.gridOverlayView addSubview:lineView];
        
        if (i < 2) {
            // Horizontal lines at 1/3 and 2/3
            [NSLayoutConstraint activateConstraints:@[
                [lineView.leadingAnchor constraintEqualToAnchor:self.gridOverlayView.leadingAnchor],
                [lineView.trailingAnchor constraintEqualToAnchor:self.gridOverlayView.trailingAnchor],
                [lineView.heightAnchor constraintEqualToConstant:lineWidth],
                [lineView.topAnchor constraintEqualToAnchor:self.gridOverlayView.topAnchor constant:self.gridOverlayView.bounds.size.height * (i + 1) / 3.0]
            ]];
        } else {
            // Vertical lines at 1/3 and 2/3
            [NSLayoutConstraint activateConstraints:@[
                [lineView.topAnchor constraintEqualToAnchor:self.gridOverlayView.topAnchor],
                [lineView.bottomAnchor constraintEqualToAnchor:self.gridOverlayView.bottomAnchor],
                [lineView.widthAnchor constraintEqualToConstant:lineWidth],
                [lineView.leadingAnchor constraintEqualToAnchor:self.gridOverlayView.leadingAnchor constant:self.gridOverlayView.bounds.size.width * (i - 1) / 3.0]
            ]];
        }
    }
}

#pragma mark - SDK and Camera Setup

- (void)setupNosmaiCore {
    [NosmaiCore shared].delegate = self;
    [[NosmaiCore shared] initializeWithAPIKey:kNosmaiAPIKey completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self configureSDKComponents];
                [self loadFiltersInBackground];
            } else {
                [self showSDKError:error];
            }
        });
    }];
}

- (void)configureSDKComponents {
    if (self.isSDKReady) return;
    self.isSDKReady = YES;
    NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
    config.position = NosmaiCameraPositionFront;
    config.sessionPreset = AVCaptureSessionPresetHigh;
    [[NosmaiCore shared].camera updateConfiguration:config];
    [[NosmaiCore shared].camera attachToView:_previewContainerView];
    
    // 🔧 FIX: Also set preview view on NosmaiSDK to ensure proper connection
    [[NosmaiSDK sharedInstance] setPreviewView:_previewContainerView];
    
    // Set delegate to receive filter updates
    [[NosmaiSDK sharedInstance] setDelegate:self];
    
    // Update beauty button state immediately
    [self updateBeautyButtonState];
    
    // Check again after a short delay to catch async license verification
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateBeautyButtonState];
    });
    
    // Check once more after a longer delay to ensure we catch any delayed license verification
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateBeautyButtonState];
    });

    if (self.viewIfLoaded.window) [self startCameraCapture];
}

- (void)startCameraCapture {
    if (!self.isSDKReady) return;
    
    [[NosmaiCore shared].camera startCapture];
    
    [[NosmaiSDK sharedInstance] startProcessing];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateCameraPreviewFrame];
        
        // Add smooth fade-in animation for camera preview
        [UIView animateWithDuration:0.6
                              delay:0.1
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self.previewContainerView.alpha = 1.0;
        } completion:^(BOOL finished) {
            // Animation completed
            NSLog(@"📱 Camera preview transition completed smoothly");
        }];
    });
}

- (void)updateCameraPreviewFrame {
    if (!self.isSDKReady) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *subview in self.previewContainerView.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"NosmaiView")]) {
                subview.frame = self.previewContainerView.bounds;
                id nosmaiView = subview;
                if ([nosmaiView respondsToSelector:@selector(setFillMode:)]) {
                    [nosmaiView setValue:@(2) forKey:@"fillMode"];
                }
                break;
            }
        }
    });
}

- (void)deviceOrientationDidChange {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateCameraPreviewFrame];
    });
}

- (void)showSDKError:(NSError *)error {
    if (!self.viewIfLoaded.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SDK Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self closeController];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Filter Management

- (void)loadFiltersInBackground {
    // Get initial filters synchronously for immediate UI display
    NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [[NosmaiSDK sharedInstance] getInitialFilters];
    
    // Process the organized filters
    [self processOrganizedFilters:organizedFilters];
    
    // Update UI immediately with local filters
    [self transitionFromPlaceholdersToFilters];
    
    // Trigger background cloud filter fetch only if network is available
    if ([self isNetworkAvailable]) {
        [[NosmaiSDK sharedInstance] fetchCloudFilters];
    } else {
        // No network - don't show loading toast, just use local/cached filters
        self.isLoadingCloudFilters = NO;
        NSLog(@"📱 No network connection, skipping cloud filter fetch");
    }
}

- (void)retryFilterLoadingIfNeeded {
    // Only retry if SDK is ready but filters haven't loaded
    if (self.isSDKReady && (!self.onlyFiltersArray || self.onlyFiltersArray.count == 0 || !self.onlyEffectsArray || self.onlyEffectsArray.count == 0)) {
        NSLog(@"🔄 Retrying filter loading...");
        [self loadFiltersInBackground];
    } else if (!self.isSDKReady) {
        // SDK not ready yet, try again after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self retryFilterLoadingIfNeeded];
        });
    }
}

- (void)processOrganizedFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*> *)organizedFilters {
    // Store the organized filters
    self.organizedFilters = organizedFilters;
    
    // Create the clear filter
    NSDictionary *clearFilter = @{
        @"name": @"clear",
        @"displayName": @"None",
        @"type": @"special"
    };
    
    // Create carousel data source starting with clear filter
    NSMutableArray *carouselDataSource = [NSMutableArray arrayWithObject:clearFilter];
    
    // Extract filters and effects arrays for bottom sheets
    NSMutableArray *filtersArray = [NSMutableArray array];
    NSMutableArray *effectsArray = [NSMutableArray array];
    
    // Process all filter types
    for (NSString *filterType in organizedFilters.allKeys) {
        NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
        
        // Process each filter and ensure cloud filters have proper properties
        for (NSDictionary *filter in filtersOfType) {
            NSMutableDictionary *processedFilter = [filter mutableCopy];
            
            // For cloud filters without a path, ensure they're marked as not downloaded
            if ([processedFilter[@"type"] isEqualToString:@"cloud"] && !processedFilter[@"path"]) {
                processedFilter[@"isDownloaded"] = @NO;
                
                // If there's a localPath from a previous download, use it
                if (processedFilter[@"localPath"]) {
                    processedFilter[@"path"] = processedFilter[@"localPath"];
                    processedFilter[@"isDownloaded"] = @YES;
                }
            }
            
            // Ensure all filters have a displayName
            if (!processedFilter[@"displayName"] && processedFilter[@"name"]) {
                processedFilter[@"displayName"] = processedFilter[@"name"];
            }
            
            NSDictionary *finalFilter = [processedFilter copy];
            
            // For cloud filters, categorize based on filterCategory
            if ([finalFilter[@"type"] isEqualToString:@"cloud"] && finalFilter[@"filterCategory"]) {
                NSString *category = finalFilter[@"filterCategory"];
                
                if ([category isEqualToString:@"beauty-effects"] || [category isEqualToString:@"special-effects"]) {
                    // These go to Effects sheet
                    [effectsArray addObject:finalFilter];
                   
                } else if ([category isEqualToString:@"cloud-filters"] || [category isEqualToString:@"fx-and-filters"]) {
                    // These go to Filters sheet
                    [filtersArray addObject:finalFilter];
                   
                } else {
                    // Unknown category - default to original behavior
                    if ([filterType isEqualToString:@"filter"]) {
                        [filtersArray addObject:finalFilter];
                    } else if ([filterType isEqualToString:@"effect"]) {
                        [effectsArray addObject:finalFilter];
                    }
                }
            } else {
                // Non-cloud filters or cloud filters without category - use original logic
                if ([filterType isEqualToString:@"filter"]) {
                    [filtersArray addObject:finalFilter];
                } else if ([filterType isEqualToString:@"effect"]) {
                    [effectsArray addObject:finalFilter];
                }
            }
            
            // Add all filters to carousel
            [carouselDataSource addObject:finalFilter];
        }
    }
    
    // Update properties
    self.onlyFiltersArray = [filtersArray copy];
    self.onlyEffectsArray = [effectsArray copy];
    self.localFilters = [carouselDataSource copy];
}


- (void)transitionFromPlaceholdersToFilters {
    self.areFiltersLoading = NO;
    // Removed - filterCarouselView no longer exists
}


#pragma mark - Bottom Sheet Management
- (void)handleFiltersButtonPress {
    [self animateButton:self.filtersButton];
    
    // Check if SDK is ready first
    if (!self.isSDKReady) {
        [self showSDKNotReadyAlert:@"Filters are loading, please wait..."];
        [self retryFilterLoadingIfNeeded];
        return;
    }
    
    // Get available filters (local + cached cloud filters)
    NSArray *availableFilters = [self getAvailableFilters];
    if (availableFilters.count == 0) {
        // No filters available at all (not even local ones)
        [self showSDKNotReadyAlert:@"No filters available"];
        [self retryFilterLoadingIfNeeded];
        return;
    }
    
    // Rest of existing code...
    if (self.bottomSheetView.superview && [self.currentBottomSheetType isEqualToString:@"Filters"]) {
        [self dismissBottomSheet];
        return;
    }
    
    if (self.bottomSheetView.superview) {
        [self dismissBottomSheetWithCompletion:^{
            // Use available filters instead of onlyFiltersArray
            self.bottomSheetDataSource = availableFilters;
            self.currentBottomSheetType = @"Filters";
            [self showBottomSheetWithTitle:@"Filters"];
        }];
    } else {
        // Use available filters instead of onlyFiltersArray
        self.bottomSheetDataSource = availableFilters;
        self.currentBottomSheetType = @"Filters";
        [self showBottomSheetWithTitle:@"Filters"];
    }
}

// Updated Effect Button
- (void)handleEffectsButtonPress {
    [self animateButton:self.effectsButton];
    
    // Check if SDK is ready first
    if (!self.isSDKReady) {
        [self showSDKNotReadyAlert:@"Effects are loading, please wait..."];
        [self retryFilterLoadingIfNeeded];
        return;
    }
    
    // Get available effects (local + cached cloud effects)
    NSArray *availableEffects = [self getAvailableEffects];
    if (availableEffects.count == 0) {
        // No effects available at all (not even local ones)
        [self showSDKNotReadyAlert:@"No effects available"];
        [self retryFilterLoadingIfNeeded];
        return;
    }
    
    if (self.bottomSheetView.superview && [self.currentBottomSheetType isEqualToString:@"Effects"]) {
        [self dismissBottomSheet];
        return;
    }
    
    if (self.bottomSheetView.superview) {
        [self dismissBottomSheetWithCompletion:^{
            // Use available effects instead of onlyEffectsArray
            self.bottomSheetDataSource = availableEffects;
            self.currentBottomSheetType = @"Effects";
            [self showBottomSheetWithTitle:@"Effects"];
        }];
    } else {
        // Use available effects instead of onlyEffectsArray
        self.bottomSheetDataSource = availableEffects;
        self.currentBottomSheetType = @"Effects";
        [self showBottomSheetWithTitle:@"Effects"];
    }
}


- (void)animateButton:(UIButton *)button {
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
    
    // Simple scale animation
    [UIView animateWithDuration:0.15 animations:^{
        button.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            button.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)animateButtonWithSpark:(UIButton *)button {
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    
    // Scale animation with bounce effect
    [UIView animateWithDuration:0.1 animations:^{
        button.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:0
             usingSpringWithDamping:0.6
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            button.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    
    // Add spark particles animation
    [self addSparkParticlesAroundButton:button];
}

- (void)addSparkParticlesAroundButton:(UIButton *)button {
    for (int i = 0; i < 8; i++) {
        UIView *spark = [[UIView alloc] init];
        spark.backgroundColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0];
        spark.frame = CGRectMake(0, 0, 4, 4);
        spark.layer.cornerRadius = 2.0;
        spark.center = button.center;
        [button.superview addSubview:spark];
        
        // Random angle for each spark
        CGFloat angle = (M_PI * 2 * i) / 8.0;
        CGFloat distance = 30.0 + (arc4random() % 20);
        CGFloat endX = button.center.x + cos(angle) * distance;
        CGFloat endY = button.center.y + sin(angle) * distance;
        
        [UIView animateWithDuration:0.6
                              delay:0.1
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            spark.center = CGPointMake(endX, endY);
            spark.alpha = 0.0;
            spark.transform = CGAffineTransformMakeScale(0.1, 0.1);
        } completion:^(BOOL finished) {
            [spark removeFromSuperview];
        }];
    }
}

#pragma mark - Beauty Filters Methods

- (void)updateBeautyButtonState {
    BOOL beautyEnabled = [[NosmaiCore shared].effects isBeautyEffectEnabled];
    self.beautyButton.enabled = beautyEnabled;
    self.beautyButton.alpha = beautyEnabled ? 1.0 : 0.4;
    
 
}

- (void)handleBeautyButtonPress {
    [self animateButton:self.beautyButton];
    
    // Check if SDK is ready
    if (!self.isSDKReady) {
        [self showSDKNotReadyAlert:@"Beauty filters are loading, please wait..."];
        return;
    }
    
    if (self.beautyBottomSheet && self.beautyBottomSheet.superview) {
        [self dismissBeautyBottomSheet];
    } else {
        [self synchronizeBeautyUIState];
        
        [self showBeautyBottomSheet];
    }
}


- (void)synchronizeBeautyUIState {
    BOOL areBuiltInFiltersActiveInSDK = [[NosmaiSDK sharedInstance] hasActiveBuiltInFilters];
    if (!areBuiltInFiltersActiveInSDK && self.activeBeautyFilters.count > 0) {
        NSLog(@"🧹 Syncing UI: SDK has no built-in filters, but UI does. Resetting UI state.");

        // Saare models ko reset karein
        for (BeautyFilterModel *filter in self.beautyFilters) {
            filter.isActive = NO;
            filter.currentValue = filter.defaultValue;
        }
        
        [self.activeBeautyFilters removeAllObjects];
        
        if (self.sliderContainerView && !self.sliderContainerView.hidden) {
            [self hideSlider];
        }
        
        if (self.beautyFiltersCollectionView) {
            [self.beautyFiltersCollectionView reloadData];
        }
    }
}

- (void)showBeautyBottomSheet {
    CGFloat safeAreaBottom = self.view.safeAreaInsets.bottom;
    CGFloat sheetHeight = 220 + safeAreaBottom; // Increased height for better spacing
    
    self.beautyBottomSheet = [[UIView alloc] init];
    self.beautyBottomSheet.backgroundColor = [UIColor clearColor];
    self.beautyBottomSheet.clipsToBounds = YES;
    self.beautyBottomSheet.layer.cornerRadius = 20.0;
    self.beautyBottomSheet.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.beautyBottomSheet.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.beautyBottomSheet];
    
    // Add blur effect
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.layer.cornerRadius = 20.0;
    blurView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    blurView.clipsToBounds = YES;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.beautyBottomSheet addSubview:blurView];
    
    // Grabber view
    UIView *grabberView = [[UIView alloc] init];
    grabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    grabberView.layer.cornerRadius = 2.5;
    grabberView.translatesAutoresizingMaskIntoConstraints = NO;
    [blurView.contentView addSubview:grabberView];
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Beauty Filters";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [blurView.contentView addSubview:titleLabel];
    
    // Reset button
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    resetButton.layer.cornerRadius = 15;
    resetButton.clipsToBounds = YES;
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton addTarget:self action:@selector(resetAllBeautyFilters) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:resetButton];
    
    // Collection view layout with responsive sizing
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    
    // Responsive item sizing based on screen width
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat itemWidth = MAX(65, MIN(80, (screenWidth - 80) / 5)); // 5 items visible with padding
    CGFloat itemHeight = itemWidth + 25; // Height includes label space
    
    layout.itemSize = CGSizeMake(itemWidth, itemHeight);
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
    
    // Collection view
    self.beautyFiltersCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.beautyFiltersCollectionView.backgroundColor = [UIColor clearColor];
    self.beautyFiltersCollectionView.dataSource = self;
    self.beautyFiltersCollectionView.delegate = self;
    self.beautyFiltersCollectionView.showsHorizontalScrollIndicator = NO;
    self.beautyFiltersCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.beautyFiltersCollectionView registerClass:[BeautyFilterCell class] forCellWithReuseIdentifier:@"BeautyFilterCell"];
    [blurView.contentView addSubview:self.beautyFiltersCollectionView];
    
    // Bottom sheet constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.beautyBottomSheet.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.beautyBottomSheet.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.beautyBottomSheet.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.beautyBottomSheet.heightAnchor constraintEqualToConstant:sheetHeight]
    ]];
    
    // Blur view constraints
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:self.beautyBottomSheet.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:self.beautyBottomSheet.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.beautyBottomSheet.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:self.beautyBottomSheet.bottomAnchor]
    ]];
    
    // Content constraints with proper spacing
    [NSLayoutConstraint activateConstraints:@[
        // Grabber
        [grabberView.topAnchor constraintEqualToAnchor:blurView.contentView.topAnchor constant:10],
        [grabberView.centerXAnchor constraintEqualToAnchor:blurView.contentView.centerXAnchor],
        [grabberView.widthAnchor constraintEqualToConstant:36],
        [grabberView.heightAnchor constraintEqualToConstant:4],
        
        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:grabberView.bottomAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:blurView.contentView.leadingAnchor constant:20],
        
        // Reset button
        [resetButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [resetButton.trailingAnchor constraintEqualToAnchor:blurView.contentView.trailingAnchor constant:-20],
        [resetButton.widthAnchor constraintEqualToConstant:60],
        [resetButton.heightAnchor constraintEqualToConstant:28],
        
        // Collection view with proper spacing
        [self.beautyFiltersCollectionView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [self.beautyFiltersCollectionView.leadingAnchor constraintEqualToAnchor:blurView.contentView.leadingAnchor],
        [self.beautyFiltersCollectionView.trailingAnchor constraintEqualToAnchor:blurView.contentView.trailingAnchor],
        [self.beautyFiltersCollectionView.bottomAnchor constraintEqualToAnchor:blurView.contentView.safeAreaLayoutGuide.bottomAnchor constant:-10]
    ]];
    
    // Add tap gesture to dismiss
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBeautySheetBackgroundTap:)];
    tapGesture.cancelsTouchesInView = NO;
    tapGesture.delegate = self;
    tapGesture.name = @"BeautySheetDismissTap";
    [self.view addGestureRecognizer:tapGesture];
    
    // Initial position (off screen)
    self.beautyBottomSheet.transform = CGAffineTransformMakeTranslation(0, sheetHeight);
    
    // Animate in with spring animation
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.beautyBottomSheet.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissBeautyBottomSheet {
    if (!self.beautyBottomSheet) return;
    
    // Hide slider if it's visible
    if (self.sliderContainerView && !self.sliderContainerView.hidden) {
        [self hideSlider];
    }
    
    if (self.sliderContainerView) {
            [self.sliderContainerView removeFromSuperview];
            self.sliderContainerView = nil;
            self.activeFilterSlider = nil;
            self.sliderTitleLabel = nil;
            self.sliderValueLabel = nil;
        }

    
    
    CGFloat sheetHeight = self.beautyBottomSheet.frame.size.height;
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.beautyBottomSheet.transform = CGAffineTransformMakeTranslation(0, sheetHeight);
    } completion:^(BOOL finished) {
        [self.beautyBottomSheet removeFromSuperview];
        self.beautyBottomSheet = nil;
        self.beautyFiltersCollectionView = nil;
        
        // Remove tap gesture
        for (UIGestureRecognizer *recognizer in self.view.gestureRecognizers) {
            if ([recognizer isKindOfClass:[UITapGestureRecognizer class]] &&
                recognizer.delegate == self &&
                [recognizer.name isEqualToString:@"BeautySheetDismissTap"]) {
                [self.view removeGestureRecognizer:recognizer];
                break;
            }
        }
    }];
}

- (void)handleBeautySheetBackgroundTap:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    CGRect sheetFrame = self.beautyBottomSheet.frame;
    
    // Account for any transform when checking if tap is outside sheet
    if (!CGRectContainsPoint(sheetFrame, location)) {
        [self dismissBeautyBottomSheet];
    }
}

- (void)sliderValueChanged:(UISlider *)slider {
    if (!self.currentSliderFilter) return;
    
    self.currentSliderFilter.currentValue = slider.value;
    
    // Update value label
    if (self.currentSliderFilter.minValue < 0) {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.1f", slider.value];
    } else {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.0f", slider.value];
    }
    
    // Apply the filter
    [self applyBeautyFilter:self.currentSliderFilter];
}

- (void)resetCurrentFilter {
    if (!self.currentSliderFilter) return;
    
    // Update the current filter values
    self.currentSliderFilter.currentValue = self.currentSliderFilter.defaultValue;
    self.currentSliderFilter.isActive = NO;
    self.activeFilterSlider.value = self.currentSliderFilter.defaultValue;
    
    // IMPORTANT: Also update the filter in the main beautyFilters array
    for (BeautyFilterModel *filter in self.beautyFilters) {
        if ([filter.identifier isEqualToString:self.currentSliderFilter.identifier]) {
            filter.currentValue = filter.defaultValue;
            filter.isActive = NO;
            break;
        }
    }
    
    // Update value label
    if (self.currentSliderFilter.minValue < 0) {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.1f", self.currentSliderFilter.defaultValue];
    } else {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.0f", self.currentSliderFilter.defaultValue];
    }
    
    // Force apply the beauty filter to ensure SDK state is updated
    [self applyBeautyFilter:self.currentSliderFilter];
    
    // For BeautyFaceFilter-based filters, ensure the SDK state is properly synchronized
    if ([self.currentSliderFilter.identifier isEqualToString:@"skin_smoothing"] ||
        [self.currentSliderFilter.identifier isEqualToString:@"skin_whitening"] ||
        [self.currentSliderFilter.identifier isEqualToString:@"sharpening"]) {
        
        // Immediately remove from activeBeautyFilters to ensure clean state
        [self.activeBeautyFilters removeObjectForKey:self.currentSliderFilter.identifier];
        
        // Update collection view to reflect the change
        [self.beautyFiltersCollectionView reloadData];
    }
}

- (void)showSliderForFilter:(BeautyFilterModel *)filter {
    self.currentSliderFilter = filter;
    
    // Create slider container if it doesn't exist
    if (!self.sliderContainerView) {
        [self createSliderContainer];
    }
    
    // Update slider properties
    self.activeFilterSlider.minimumValue = filter.minValue;
    self.activeFilterSlider.maximumValue = filter.maxValue;
    self.activeFilterSlider.value = filter.currentValue;
    
    // Update labels
    self.sliderTitleLabel.text = [filter.displayName stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    
    if (filter.minValue < 0) {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.1f", filter.currentValue];
    } else {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%.0f", filter.currentValue];
    }
    
    // Show slider with animation
    if (self.sliderContainerView.hidden) {
        self.sliderContainerView.hidden = NO;
        self.sliderContainerView.alpha = 0;
        self.sliderContainerView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        
        // Optional: layoutIfNeeded() for smoother animation
        [self.view layoutIfNeeded];

        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.sliderContainerView.alpha = 1.0;
            self.sliderContainerView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)createSliderContainer {
    // Slider container
    self.sliderContainerView = [[UIView alloc] init];
    self.sliderContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sliderContainerView.layer.cornerRadius = 15;
    self.sliderContainerView.clipsToBounds = YES;
    self.sliderContainerView.hidden = YES;

    // Add blur effect to slider container
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sliderContainerView addSubview:blurView];

    [self.view addSubview:self.sliderContainerView];

    [NSLayoutConstraint activateConstraints:@[
        // Yahan isse beauty sheet ke ooper rakhenge
        [self.sliderContainerView.bottomAnchor constraintEqualToAnchor:self.beautyBottomSheet.topAnchor constant:-20],
        [self.sliderContainerView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.sliderContainerView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.sliderContainerView.heightAnchor constraintEqualToConstant:80] // Fixed height
    ]];

    // Constraints for blur view to fill container
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:self.sliderContainerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:self.sliderContainerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.sliderContainerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:self.sliderContainerView.bottomAnchor]
    ]];

    // Slider title
    self.sliderTitleLabel = [[UILabel alloc] init];
    self.sliderTitleLabel.textColor = [UIColor whiteColor];
    self.sliderTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.sliderTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [blurView.contentView addSubview:self.sliderTitleLabel];

    // Slider value label
    self.sliderValueLabel = [[UILabel alloc] init];
    self.sliderValueLabel.textColor = [UIColor whiteColor];
    self.sliderValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.sliderValueLabel.textAlignment = NSTextAlignmentRight;
    self.sliderValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [blurView.contentView addSubview:self.sliderValueLabel];

    // Slider
    self.activeFilterSlider = [[UISlider alloc] init];
    self.activeFilterSlider.minimumTrackTintColor = [UIColor systemBlueColor];
    self.activeFilterSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    self.activeFilterSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activeFilterSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [blurView.contentView addSubview:self.activeFilterSlider];

    // Reset button
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    resetButton.tintColor = [UIColor whiteColor];
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton addTarget:self action:@selector(resetCurrentFilter) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:resetButton];

    // Constraints for slider contents
    [NSLayoutConstraint activateConstraints:@[
        // Slider title
        [self.sliderTitleLabel.topAnchor constraintEqualToAnchor:blurView.contentView.topAnchor constant:10],
        [self.sliderTitleLabel.leadingAnchor constraintEqualToAnchor:blurView.contentView.leadingAnchor constant:15],
        
        // Slider value
        [self.sliderValueLabel.centerYAnchor constraintEqualToAnchor:self.sliderTitleLabel.centerYAnchor],
        [self.sliderValueLabel.trailingAnchor constraintEqualToAnchor:blurView.contentView.trailingAnchor constant:-15],
        [self.sliderValueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],
        
        // Reset button
        [resetButton.centerYAnchor constraintEqualToAnchor:self.sliderTitleLabel.centerYAnchor],
        [resetButton.trailingAnchor constraintEqualToAnchor:self.sliderValueLabel.leadingAnchor constant:-10],
        
        // Slider
        [self.activeFilterSlider.centerYAnchor constraintEqualToAnchor:blurView.contentView.centerYAnchor constant:10],
        [self.activeFilterSlider.leadingAnchor constraintEqualToAnchor:blurView.contentView.leadingAnchor constant:15],
        [self.activeFilterSlider.trailingAnchor constraintEqualToAnchor:blurView.contentView.trailingAnchor constant:-15],
    ]];
}
- (void)hideSlider {
    [UIView animateWithDuration:0.3 animations:^{
        self.sliderContainerView.alpha = 0.0;
        self.sliderContainerView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        self.sliderContainerView.hidden = YES;
        self.currentSliderFilter = nil;
    }];
}

- (void)applyBeautyFilter:(BeautyFilterModel *)filter {
    NSString *methodName = filter.methodName;
    NosmaiEffectsEngine *effects = [NosmaiCore shared].effects;
    
    if (filter.type == BeautyFilterTypeSlider) {
        // Check if we need to remove the filter (when slider is at default value)
        if (filter.currentValue == filter.defaultValue) {
            // Mark as inactive and remove from active filters
            filter.isActive = NO;
            [self.activeBeautyFilters removeObjectForKey:filter.identifier];
            
            // Special handling for BeautyFaceFilter shared by multiple controls
            if ([filter.identifier isEqualToString:@"skin_smoothing"] ||
                [filter.identifier isEqualToString:@"skin_whitening"] ||
                [filter.identifier isEqualToString:@"sharpening"]) {
                
                // IMPORTANT: First apply the filter with default value to reset it in SDK
                // This must happen BEFORE checking other filters to ensure SDK state is clean
                SEL selector = NSSelectorFromString(filter.methodName);
                if ([effects respondsToSelector:selector]) {
                    NSMethodSignature *signature = [effects methodSignatureForSelector:selector];
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:effects];
                    [invocation setSelector:selector];
                    float defaultValue = filter.defaultValue;
                    [invocation setArgument:&defaultValue atIndex:2];
                    [invocation invoke];
                }
                
                // Only remove BeautyFaceFilter if no other related filters are active
                BOOL otherBeautyFaceFiltersActive = NO;
                if (![filter.identifier isEqualToString:@"skin_smoothing"]) {
                    BeautyFilterModel *smoothingFilter = self.activeBeautyFilters[@"skin_smoothing"];
                    if (smoothingFilter && smoothingFilter.currentValue != smoothingFilter.defaultValue) {
                        otherBeautyFaceFiltersActive = YES;
                    }
                }
                if (![filter.identifier isEqualToString:@"skin_whitening"]) {
                    BeautyFilterModel *whiteningFilter = self.activeBeautyFilters[@"skin_whitening"];
                    if (whiteningFilter && whiteningFilter.currentValue != whiteningFilter.defaultValue) {
                        otherBeautyFaceFiltersActive = YES;
                    }
                }
                if (![filter.identifier isEqualToString:@"sharpening"]) {
                    BeautyFilterModel *sharpeningFilter = self.activeBeautyFilters[@"sharpening"];
                    if (sharpeningFilter && sharpeningFilter.currentValue != sharpeningFilter.defaultValue) {
                        otherBeautyFaceFiltersActive = YES;
                    }
                }
                
                // If no other filters using BeautyFaceFilter are active, remove it
                if (!otherBeautyFaceFiltersActive) {
                    [[NosmaiCore shared].effects removeBuiltInFilterByName:@"BeautyFaceFilter"];
                } else {
                    // Re-apply other active filters that use BeautyFaceFilter
                    [self reapplyActiveBeautyFaceFilters:filter.identifier];
                }
            } else if ([filter.identifier isEqualToString:@"lipstick"]) {
                [[NosmaiCore shared].effects removeBuiltInFilterByName:@"LipstickFilter"];
            } else if ([filter.identifier isEqualToString:@"blusher"]) {
                [[NosmaiCore shared].effects removeBuiltInFilterByName:@"BlusherFilter"];
            } else if ([filter.identifier hasPrefix:@"red_channel"] || [filter.identifier hasPrefix:@"green_channel"] || [filter.identifier hasPrefix:@"blue_channel"]) {
                // For RGB filters, check if all channels are at default
                BeautyFilterModel *redFilter = self.activeBeautyFilters[@"red_channel"];
                BeautyFilterModel *greenFilter = self.activeBeautyFilters[@"green_channel"];
                BeautyFilterModel *blueFilter = self.activeBeautyFilters[@"blue_channel"];
                
                // If all RGB channels are inactive or at default, remove the RGB filter
                if ((!redFilter || redFilter.currentValue == 1.0f) &&
                    (!greenFilter || greenFilter.currentValue == 1.0f) &&
                    (!blueFilter || blueFilter.currentValue == 1.0f)) {
                    [[NosmaiCore shared].effects removeBuiltInFilterByName:@"RGBFilter"];
                } else {
                    // Otherwise, reapply with remaining active values
                    float red = redFilter ? redFilter.currentValue : 1.0f;
                    float green = greenFilter ? greenFilter.currentValue : 1.0f;
                    float blue = blueFilter ? blueFilter.currentValue : 1.0f;
                    [[NosmaiCore shared].effects applyRGBFilterWithRed:red green:green blue:blue];
                }
            } else {
                NSString *filterName = [self getFilterNameForIdentifier:filter.identifier];
                [[NosmaiCore shared].effects removeBuiltInFilterByName:filterName];
            }
        } else {
            // Apply or update the filter (when value is not default)
            // Apply the filter
            filter.isActive = YES;
            self.activeBeautyFilters[filter.identifier] = filter;
            
            // Apply to SDK
            if ([filter.identifier isEqualToString:@"lipstick"] || [filter.identifier isEqualToString:@"blusher"]) {
                NSString *filterType = [filter.identifier isEqualToString:@"lipstick"] ? @"LipstickFilter" : @"BlusherFilter";
                SEL selector = NSSelectorFromString(methodName);
                if ([effects respondsToSelector:selector]) {
                    NSMethodSignature *signature = [effects methodSignatureForSelector:selector];
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:effects];
                    [invocation setSelector:selector];
                    [invocation setArgument:&filterType atIndex:2];
                    float value = filter.currentValue;
                    [invocation setArgument:&value atIndex:3];
                    [invocation invoke];
                }
            } else if ([filter.identifier isEqualToString:@"saturation"]) {
                // For HSB adjustment, we need to pass hue, saturation, brightness
                [effects adjustHSBWithHue:0.0f saturation:filter.currentValue brightness:1.0f];
            } else if ([filter.identifier isEqualToString:@"temperature"]) {
                // For white balance, pass temperature and tint (tint = 0)
                [effects applyWhiteBalanceWithTemperature:filter.currentValue tint:0.0f];
            } else if ([filter.identifier hasPrefix:@"red_channel"] || [filter.identifier hasPrefix:@"green_channel"] || [filter.identifier hasPrefix:@"blue_channel"]) {
                // For RGB filters, we need to get all current values
                float red = 1.0f, green = 1.0f, blue = 1.0f;
                
                // Get current values from active filters
                BeautyFilterModel *redFilter = self.activeBeautyFilters[@"red_channel"];
                BeautyFilterModel *greenFilter = self.activeBeautyFilters[@"green_channel"];
                BeautyFilterModel *blueFilter = self.activeBeautyFilters[@"blue_channel"];
                
                if (redFilter) red = redFilter.currentValue;
                if (greenFilter) green = greenFilter.currentValue;
                if (blueFilter) blue = blueFilter.currentValue;
                
                // Update the current channel
                if ([filter.identifier isEqualToString:@"red_channel"]) red = filter.currentValue;
                else if ([filter.identifier isEqualToString:@"green_channel"]) green = filter.currentValue;
                else if ([filter.identifier isEqualToString:@"blue_channel"]) blue = filter.currentValue;
                
                [effects applyRGBFilterWithRed:red green:green blue:blue];
            } else {
                // Special handling for BeautyFaceFilter filters
                if ([filter.identifier isEqualToString:@"skin_smoothing"] ||
                    [filter.identifier isEqualToString:@"skin_whitening"] ||
                    [filter.identifier isEqualToString:@"sharpening"]) {
                    
                    
                    // Check if proper method exists in SDK
                    SEL selector = NSSelectorFromString(methodName);
                    if ([effects respondsToSelector:selector]) {
                        NSMethodSignature *signature = [effects methodSignatureForSelector:selector];
                        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                        [invocation setTarget:effects];
                        [invocation setSelector:selector];
                        float value = filter.currentValue;
                        [invocation setArgument:&value atIndex:2];
                        [invocation invoke];
                        
                    } else {
                        NSLog(@"❌ ERROR: Method %@ not found in NosmaiEffectsEngine", methodName);
                    }
                } else {
                    SEL selector = NSSelectorFromString(methodName);
                    if ([effects respondsToSelector:selector]) {
                        NSMethodSignature *signature = [effects methodSignatureForSelector:selector];
                        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                        [invocation setTarget:effects];
                        [invocation setSelector:selector];
                        float value = filter.currentValue;
                        [invocation setArgument:&value atIndex:2];
                        [invocation invoke];
                    }
                }
            }
        }
    } else if (filter.type == BeautyFilterTypeToggle) {
        filter.isActive = !filter.isActive;
        
        if (filter.isActive) {
            self.activeBeautyFilters[filter.identifier] = filter;
            SEL selector = NSSelectorFromString(methodName);
            if ([effects respondsToSelector:selector]) {
                [effects performSelector:selector];
            }
        } else {
            [self.activeBeautyFilters removeObjectForKey:filter.identifier];
            NSString *filterName = [self getFilterNameForIdentifier:filter.identifier];
            [[NosmaiCore shared].effects removeBuiltInFilterByName:filterName];
        }
    }
    
    // Reload collection view to update UI
    [self.beautyFiltersCollectionView reloadData];
}

- (void)reapplyActiveBeautyFaceFilters:(NSString *)excludeIdentifier {
    NosmaiEffectsEngine *effects = [NosmaiCore shared].effects;
    
    // Process each BeautyFaceFilter-based filter that is still active
    NSArray *beautyFaceFilters = @[@"skin_smoothing", @"skin_whitening", @"sharpening"];
    
    for (NSString *identifier in beautyFaceFilters) {
        // Skip the filter we're currently removing
        if ([identifier isEqualToString:excludeIdentifier]) {
            continue;
        }
        
        // Only look for filters in activeBeautyFilters dictionary
        BeautyFilterModel *filter = self.activeBeautyFilters[identifier];
        if (filter) {
            // Only reapply if filter has a non-default value
            if (filter.currentValue != filter.defaultValue) {
                SEL selector = NSSelectorFromString(filter.methodName);
                if ([effects respondsToSelector:selector]) {
                    NSMethodSignature *signature = [effects methodSignatureForSelector:selector];
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:effects];
                    [invocation setSelector:selector];
                    float value = filter.currentValue;
                    [invocation setArgument:&value atIndex:2];
                    [invocation invoke];
                }
            }
        }
    }
}




- (NSString *)getFilterNameForIdentifier:(NSString *)identifier {
    NSDictionary *filterNameMap = @{
        @"brightness": @"BrightnessFilter",
        @"contrast": @"ContrastFilter",
        @"hue": @"HueFilter",
        @"grayscale": @"GrayscaleFilter",
        @"temperature": @"WhiteBalanceFilter",
        
        @"skin_smoothing": @"BeautyFaceFilter",
        @"skin_whitening": @"BeautyFaceFilter",
        @"sharpening": @"BeautyFaceFilter",
        
        @"face_slimming": @"FaceReshapeFilter",
        @"eye_enlargement": @"FaceReshapeFilter",
        
        @"nose_size": @"NoseSizeFilter",
        
        @"lipstick": @"LipstickFilter",
        @"blusher": @"BlusherFilter",
        
        @"saturation": @"HSBFilter",
        
        @"red_channel": @"RGBFilter",
        @"green_channel": @"RGBFilter",
        @"blue_channel": @"RGBFilter",
    };
    
    return filterNameMap[identifier] ?: identifier;
}

- (NSArray<NSDictionary *> *)getAvailableFilters {
    // First, try to use the main filter arrays (includes fresh cloud filters when online)
    if (self.onlyFiltersArray && self.onlyFiltersArray.count > 0) {
        return self.onlyFiltersArray;
    }
    
    // Fallback: If main arrays are empty (offline scenario), get local and cached filters
    NSMutableArray *availableFilters = [NSMutableArray array];
    
    if (self.localFilters) {
        for (NSDictionary *filter in self.localFilters) {
            NSString *category = filter[@"category"];
            if (!category || [category isEqualToString:@"filter"]) {
                // Include local filters and downloaded cloud filters only
                if (![filter[@"type"] isEqualToString:@"cloud"] || [filter[@"isDownloaded"] boolValue]) {
                    [availableFilters addObject:filter];
                }
            }
        }
    }
    
    return [availableFilters copy];
}

- (NSArray<NSDictionary *> *)getAvailableEffects {
    // First, try to use the main effects arrays (includes fresh cloud effects when online)
    if (self.onlyEffectsArray && self.onlyEffectsArray.count > 0) {
        return self.onlyEffectsArray;
    }
    
    // Fallback: If main arrays are empty (offline scenario), get local and cached effects
    NSMutableArray *availableEffects = [NSMutableArray array];
    
    if (self.localFilters) {
        for (NSDictionary *filter in self.localFilters) {
            NSString *category = filter[@"category"];
            if ([category isEqualToString:@"effect"]) {
                // Include local effects and downloaded cloud effects only
                if (![filter[@"type"] isEqualToString:@"cloud"] || [filter[@"isDownloaded"] boolValue]) {
                    [availableEffects addObject:filter];
                }
            }
        }
    }
    
    return [availableEffects copy];
}

- (BOOL)isNetworkAvailable {
    // Simple network availability check using SystemConfiguration
    // This is fast and doesn't require actual network requests
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)&zeroAddress);
    
    if (reachability != NULL) {
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(reachability, &flags)) {
            CFRelease(reachability);
            return (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
        }
        CFRelease(reachability);
    }
    
    return NO;
}

- (void)removeAllBeautyFilters {
    // Remove all active beauty filters
    for (NSString *filterIdentifier in [self.activeBeautyFilters allKeys]) {
        BeautyFilterModel *filter = self.activeBeautyFilters[filterIdentifier];
        filter.currentValue = filter.defaultValue;
        filter.isActive = NO;
    }
    
    // Clear the dictionary
    [self.activeBeautyFilters removeAllObjects];
    
    // Remove all built-in filters from SDK
    [[NosmaiCore shared].effects removeBuiltInFilters];
    
    // Hide slider if visible
    if (self.sliderContainerView && !self.sliderContainerView.hidden) {
        [self hideSlider];
    }
    
    // Reload UI
    [self.beautyFiltersCollectionView reloadData];
}

- (void)resetAllBeautyFilters {
    NSLog(@"🔄 Resetting all beauty filters");
    
    // Reset all beauty filters to their default values
    for (BeautyFilterModel *filter in self.beautyFilters) {
        if (filter.isActive) {
            NSLog(@"Resetting filter: %@", filter.identifier);
            filter.currentValue = filter.defaultValue;
            filter.isActive = NO;
        }
    }
    
    // Clear active filters dictionary
    [self.activeBeautyFilters removeAllObjects];
    
    // Explicitly remove each beauty filter type from SDK
    NSArray *filterTypesToRemove = @[
        @"BeautyFaceFilter",
        @"LipstickFilter",
        @"BlusherFilter",
        @"FaceReshapeFilter",
        @"NoseSizeFilter",
        @"HSBFilter",
        @"RGBFilter",
        @"GrayscaleFilter",
        @"BrightnessFilter",
        @"ContrastFilter",
        @"HueFilter",
        @"WhiteBalanceFilter"
    ];
    
    // Remove each filter type explicitly
    for (NSString *filterType in filterTypesToRemove) {
        [[NosmaiCore shared].effects removeBuiltInFilterByName:filterType];
    }
    
    // Also call removeBuiltInFilters for good measure
    [[NosmaiCore shared].effects removeBuiltInFilters];
    
    // Force filter chain rebuild
    [[NosmaiSDK sharedInstance] forceFilterChainRebuild];
    
    // Hide slider if visible
    if (self.sliderContainerView && !self.sliderContainerView.hidden) {
        [self hideSlider];
    }
    
    // Reload collection view to update UI
    [self.beautyFiltersCollectionView reloadData];
    
    NSLog(@"✅ All beauty filters reset successfully");
}


- (void)dismissBottomSheetWithCompletion:(void(^)(void))completion {
    if (!self.bottomSheetView.superview) {
        // Sheet is already dismissed
        if (completion) completion();
        return;
    }
   
    
    CGFloat originalHeight = self.bottomSheetView.frame.size.height;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.bottomSheetView.frame = CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, originalHeight);
    } completion:^(BOOL finished) {
        [self.bottomSheetView removeFromSuperview];
        self.bottomSheetView = nil;
        self.blurEffectView = nil;
        self.bottomSheetCollectionView = nil;
        self.bottomSheetDataSource = nil;
        self.currentBottomSheetType = nil;
        
        // Remove the tap gesture recognizer
        for (UIGestureRecognizer *recognizer in self.view.gestureRecognizers) {
            if ([recognizer.name isEqualToString:@"BottomSheetDismissTap"]) {
                [self.view removeGestureRecognizer:recognizer];
                break;
            }
        }
 
        
        // Call completion handler
        if (completion) completion();
    }];
}

- (void)showBottomSheetWithTitle:(NSString *)title {
    if (self.bottomSheetView.superview) {
        NSLog(@"Bottom sheet already visible, dismissing first");
        [self dismissBottomSheetWithCompletion:^{
            [self showBottomSheetWithTitle:title];
        }];
        return;
    }
    
    CGFloat sheetHeight = self.view.bounds.size.height * 0.5; // Half screen height
    self.bottomSheetView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, sheetHeight)];
    self.bottomSheetView.clipsToBounds = YES;
    self.bottomSheetView.layer.cornerRadius = 20.0;
    self.bottomSheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.view addSubview:self.bottomSheetView];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.bottomSheetView.bounds;
    self.blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.bottomSheetView addSubview:self.blurEffectView];
    
    UIView *grabberView = [[UIView alloc] init];
    grabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    grabberView.layer.cornerRadius = 2.5;
    grabberView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blurEffectView.contentView addSubview:grabberView];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blurEffectView.contentView addSubview:titleLabel];
    
    UICollectionViewFlowLayout *sheetLayout = [[UICollectionViewFlowLayout alloc] init];
    
    // Calculate item width for 4 items per row
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat leftMargin = 15;
    CGFloat rightMargin = 15;
    CGFloat itemSpacing = 8; // Spacing between items
    CGFloat availableWidth = screenWidth - leftMargin - rightMargin - (3 * itemSpacing); // 3 gaps for 4 items
    CGFloat itemWidth = availableWidth / 4.0;
    
    sheetLayout.itemSize = CGSizeMake(itemWidth, 110);
    sheetLayout.minimumInteritemSpacing = itemSpacing;
    sheetLayout.minimumLineSpacing = 15;
    sheetLayout.sectionInset = UIEdgeInsetsMake(10, leftMargin, 10, rightMargin);
    self.bottomSheetCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:sheetLayout];
    self.bottomSheetCollectionView.backgroundColor = [UIColor clearColor];
    self.bottomSheetCollectionView.dataSource = self;
    self.bottomSheetCollectionView.delegate = self;
    self.bottomSheetCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomSheetCollectionView registerClass:[FilterCollectionViewCell class] forCellWithReuseIdentifier:kFilterCellIdentifier];
    [self.blurEffectView.contentView addSubview:self.bottomSheetCollectionView];
    
    // Create cloud filters loading indicator
    self.cloudFiltersLoadingView = [[UIView alloc] init];
    self.cloudFiltersLoadingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    self.cloudFiltersLoadingView.layer.cornerRadius = 20.0;
    self.cloudFiltersLoadingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cloudFiltersLoadingView.hidden = !self.isLoadingCloudFilters;
    [self.blurEffectView.contentView addSubview:self.cloudFiltersLoadingView];
    
    // Loading spinner
    UIActivityIndicatorView *cloudLoadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    cloudLoadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [cloudLoadingSpinner startAnimating];
    [self.cloudFiltersLoadingView addSubview:cloudLoadingSpinner];
    
    // Loading text
    UILabel *cloudLoadingLabel = [[UILabel alloc] init];
    cloudLoadingLabel.text = @"Loading more filters...";
    cloudLoadingLabel.textColor = [UIColor whiteColor];
    cloudLoadingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cloudLoadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cloudFiltersLoadingView addSubview:cloudLoadingLabel];
    
    // FIX: Create a tap gesture that doesn't interfere with the collection view
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBottomSheetBackgroundTap:)];
    tapGesture.cancelsTouchesInView = NO; // This is important!
    tapGesture.delegate = self; // Set delegate to handle touch conflicts
    tapGesture.name = @"BottomSheetDismissTap";
    [self.view addGestureRecognizer:tapGesture];
    
    [NSLayoutConstraint activateConstraints:@[
        [grabberView.topAnchor constraintEqualToAnchor:self.blurEffectView.contentView.topAnchor constant:8],
        [grabberView.centerXAnchor constraintEqualToAnchor:self.blurEffectView.contentView.centerXAnchor],
        [grabberView.widthAnchor constraintEqualToConstant:40],
        [grabberView.heightAnchor constraintEqualToConstant:5],
        [titleLabel.topAnchor constraintEqualToAnchor:grabberView.bottomAnchor constant:15],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.blurEffectView.contentView.centerXAnchor],
        [self.bottomSheetCollectionView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
        [self.bottomSheetCollectionView.leadingAnchor constraintEqualToAnchor:self.blurEffectView.contentView.leadingAnchor],
        [self.bottomSheetCollectionView.trailingAnchor constraintEqualToAnchor:self.blurEffectView.contentView.trailingAnchor],
        [self.bottomSheetCollectionView.bottomAnchor constraintEqualToAnchor:self.blurEffectView.contentView.safeAreaLayoutGuide.bottomAnchor],
        
        // Cloud loading view constraints
        [self.cloudFiltersLoadingView.bottomAnchor constraintEqualToAnchor:self.blurEffectView.contentView.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.cloudFiltersLoadingView.centerXAnchor constraintEqualToAnchor:self.blurEffectView.contentView.centerXAnchor],
        [self.cloudFiltersLoadingView.heightAnchor constraintEqualToConstant:40],
        
        // Loading spinner constraints
        [cloudLoadingSpinner.leadingAnchor constraintEqualToAnchor:self.cloudFiltersLoadingView.leadingAnchor constant:15],
        [cloudLoadingSpinner.centerYAnchor constraintEqualToAnchor:self.cloudFiltersLoadingView.centerYAnchor],
        
        // Loading label constraints
        [cloudLoadingLabel.leadingAnchor constraintEqualToAnchor:cloudLoadingSpinner.trailingAnchor constant:10],
        [cloudLoadingLabel.trailingAnchor constraintEqualToAnchor:self.cloudFiltersLoadingView.trailingAnchor constant:-15],
        [cloudLoadingLabel.centerYAnchor constraintEqualToAnchor:self.cloudFiltersLoadingView.centerYAnchor],
    ]];
    
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.bottomSheetView.frame = CGRectMake(0, self.view.bounds.size.height - sheetHeight, self.view.bounds.size.width, sheetHeight);
    } completion:nil];
}


- (void)handleBottomSheetBackgroundTap:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    
    // Check if the tap is outside the bottom sheet
    if (!CGRectContainsPoint(self.bottomSheetView.frame, location)) {
        [self dismissBottomSheet];
    }
}


- (void)cleanupFilterData {
    // Clear all filter references to free memory
    self.localFilters = nil;
    self.onlyFiltersArray = nil;
    self.onlyEffectsArray = nil;
    self.bottomSheetDataSource = nil;
    
    // Clear downloading states
    [self.downloadingFilters removeAllObjects];
    
    // Force collection view to release cells
    // [self.filterCarouselView reloadData]; // Removed - filterCarouselView no longer exists
    [self.bottomSheetCollectionView reloadData];
    
    NSLog(@"🧹 Filter data cleaned up");
}


- (void)applyFilterForIndexPath:(NSIndexPath *)indexPath forceApply:(BOOL)force {
    if (!indexPath || indexPath.item >= self.localFilters.count) {
        NSLog(@"❌ Invalid indexPath in applyFilterForIndexPath: %@", indexPath);
        return;
    }
    
    NSDictionary *filterInfo = self.localFilters[indexPath.item];
    NSString *newFilterPath = filterInfo[@"path"];
    
#ifdef DEBUG
    NSLog(@"🎯 Filter info: name=%@, type=%@, path=%@, isDownloaded=%@",
          filterInfo[@"name"], filterInfo[@"type"], newFilterPath, filterInfo[@"isDownloaded"]);
#endif
    
    // Check if same filter - IMPORTANT: Compare paths, not just index
    if ([self.currentActiveFilterPath isEqualToString:newFilterPath] && !force) {
#ifdef DEBUG
        NSLog(@"✅ Same filter already active, skipping");
#endif
        return;
    }
    
    // MEMORY FIX 1: Clear previous filter data first
    if (self.currentActiveFilterPath && ![self.currentActiveFilterPath isEqualToString:newFilterPath]) {
        // Clear decrypted data cache for previous filter
        [[NosmaiSDK sharedInstance] performSelector:@selector(clearDecryptedFilterCache)];
        
        // Force cleanup of previous filter
        @autoreleasepool {
            [[NosmaiCore shared].effects removeAllEffects];
        }
        
        // Small delay to ensure cleanup
        [NSThread sleepForTimeInterval:0.05];
    }
    
    // Update current filter path
    self.currentActiveFilterPath = newFilterPath;
    
    // Cancel any pending filter application
    [self.filterDebounceTimer invalidate];
    self.filterDebounceTimer = nil;
    
    [self.hapticGenerator impactOccurred];
    self.centeredIndexPath = indexPath;
    

    
    // MEMORY FIX 2: Use autorelease pool for filter application
    @autoreleasepool {
        if ([filterInfo[@"type"] isEqualToString:@"special"]) {
            // Clear filter
            [[NosmaiCore shared].effects removeAllEffects];
            self.currentActiveFilterPath = nil;
            return;
        }
        
        BOOL isDownloaded = [filterInfo[@"isDownloaded"] boolValue];
        if ([filterInfo[@"type"] isEqualToString:@"cloud"] && !isDownloaded) {
            // Check if already downloading to prevent duplicate downloads
            NSString *filterName = filterInfo[@"name"];
            if ([self.downloadingFilters[filterName] boolValue]) {
                NSLog(@"⏳ Filter %@ already downloading, skipping duplicate request", filterName);
                return;
            }
            
            NSLog(@"☁️ Downloading cloud filter...");
            [self downloadAndApplyCloudFilterAtIndex:indexPath];
            // Do NOT apply the filter here - it will be applied in the download completion
            return;
        }
        
        // Only apply the filter if we have a valid path
        if (newFilterPath && newFilterPath.length > 0) {
            [[NosmaiCore shared].effects applyEffect:newFilterPath completion:^(BOOL success, NSError *error) {
                if (!success) {
                    NSLog(@"Failed to apply filter: %@", error.localizedDescription);
                }
            }];
        } else {
            // Check if this is a cloud filter that needs downloading
            if ([filterInfo[@"type"] isEqualToString:@"cloud"]) {
                NSString *filterName = filterInfo[@"name"];
                // Prevent duplicate downloads
                if ([self.downloadingFilters[filterName] boolValue]) {
                    NSLog(@"⏳ Filter %@ already downloading, skipping duplicate request", filterName);
                    return;
                }
                NSLog(@"☁️ Cloud filter %@ has no local path - initiating download", filterName);
                [self downloadAndApplyCloudFilterAtIndex:indexPath];
            } else {
                NSLog(@"❌ Invalid filter path for filter: %@ (type: %@)", filterInfo[@"name"], filterInfo[@"type"]);
            }
        }
    }
    
    // MEMORY FIX 3: Trigger memory cleanup after multiple filter changes
    static NSInteger filterChangeCount = 0;
    filterChangeCount++;
    
    if (filterChangeCount >= 5) {
        filterChangeCount = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performMemoryCleanup];
        });
    }
}

- (void)performMemoryCleanup {
    NSLog(@"🧹 Performing memory cleanup after filter changes");
    
    @autoreleasepool {
        // Clear preview cache for non-visible items
        // Removed - filterCarouselView no longer exists
        
        // Clear SDK caches
        [[NosmaiSDK sharedInstance] performSelector:@selector(clearFiltersCache)];
        
        // Force garbage collection
        [[NosmaiSDK sharedInstance] performSelector:@selector(forceMemoryCleanup)];
    }
}


- (void)applySelectedNosmaiFilterWithPath:(NSString *)filterPath name:(NSString *)filterName {
    if (!self.isSDKReady) return;
    [[NosmaiCore shared].effects removeAllEffects];
    [[NosmaiCore shared].effects applyEffect:filterPath completion:nil];
}


- (void)clearAllFilters {
    // Add spark animation to clear filters button
    [self animateButtonWithSpark:self.clearFiltersButton];
    
    // Removed carousel scrolling - filterCarouselView no longer exists
    
    // Properly clear all user-added filters while preserving watermark for invalid licenses
    [[NosmaiCore shared].effects removeAllEffects];
    
    // Clear current filter tracking
    self.currentAppliedFilterName = nil;
    self.currentAppliedEffectInfo = nil;
    
    // Reset effects button to default icon
    [self updateEffectsButtonWithEffect:nil];
    
    // Also remove all beauty filters
    [self removeAllBeautyFilters];
    
    // Force memory cleanup after clearing filters
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NosmaiSDK sharedInstance] forceMemoryCleanup];
    });
}


- (void)handleFilterTypeButtonPress {
    // If the sheet is already visible, do nothing.
    if (self.bottomSheetView.superview) {
        return;
    }
    
    [self showBottomSheet];
}


- (void)showBottomSheet {
    // --- Create Container View ---
    CGFloat sheetHeight = self.view.bounds.size.height * 0.5; // Half screen height
    self.bottomSheetView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height, self.view.bounds.size.width, sheetHeight)];
    self.bottomSheetView.clipsToBounds = YES;
    self.bottomSheetView.layer.cornerRadius = 20.0;
    self.bottomSheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.view addSubview:self.bottomSheetView];
    
    // --- Create Blur Effect (Frosted Glass) ---
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.bottomSheetView.bounds;
    self.blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.bottomSheetView addSubview:self.blurEffectView];
    
    // --- Add a "Grabber" Handle ---
    UIView *grabberView = [[UIView alloc] init];
    grabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    grabberView.layer.cornerRadius = 2.5;
    grabberView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blurEffectView.contentView addSubview:grabberView];
    
    // --- Add a Title Label ---
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Filter Categories";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.blurEffectView.contentView addSubview:titleLabel];
    
    // --- Add a Dismiss Gesture ---
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissBottomSheet)];
    [self.view addGestureRecognizer:tapGesture];
    // To make sure this doesn't interfere with other taps, we'll remove it when the sheet is gone.
    tapGesture.name = @"BottomSheetDismissTap";
    
    // --- Constraints for Sheet Content ---
    [NSLayoutConstraint activateConstraints:@[
        [grabberView.topAnchor constraintEqualToAnchor:self.blurEffectView.contentView.topAnchor constant:8],
        [grabberView.centerXAnchor constraintEqualToAnchor:self.blurEffectView.contentView.centerXAnchor],
        [grabberView.widthAnchor constraintEqualToConstant:40],
        [grabberView.heightAnchor constraintEqualToConstant:5],
        
        [titleLabel.topAnchor constraintEqualToAnchor:grabberView.bottomAnchor constant:15],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.blurEffectView.contentView.centerXAnchor]
    ]];
    
    // --- Animate the sheet sliding up ---
    [UIView animateWithDuration:0.4
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.bottomSheetView.frame = CGRectMake(0, self.view.bounds.size.height - sheetHeight, self.view.bounds.size.width, sheetHeight);
    } completion:nil];
}


- (void)dismissBottomSheet {
    [self dismissBottomSheetWithCompletion:nil];
}


- (void)downloadAndApplyCloudFilterAtIndex:(NSIndexPath *)indexPath {
    NSDictionary *filterInfo = self.localFilters[indexPath.item];
    NSString *filterId = filterInfo[@"filterId"];
    NSString *filterName = filterInfo[@"name"];
    
    // Double-check to prevent race conditions
    if ([self.downloadingFilters[filterName] boolValue]) {
        NSLog(@"⏳ Filter %@ already downloading (caught in downloadAndApplyCloudFilterAtIndex), skipping", filterName);
        return;
    }
    
    self.downloadingFilters[filterName] = @YES;
    // [self.filterCarouselView reloadItemsAtIndexPaths:@[indexPath]]; // Removed
    
    // FilterCollectionViewCell *cell = (FilterCollectionViewCell *)[self.filterCarouselView cellForItemAtIndexPath:indexPath]; // Removed
    
    [[NosmaiCore shared].effects downloadCloudFilter:filterId progress:^(float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Progress tracking removed since carousel cell no longer exists
            NSLog(@"Download progress: %.2f%%", progress * 100);
        });
    } completion:^(BOOL success, NSString *localPath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.downloadingFilters removeObjectForKey:filterName];
            if (success) {
                NSMutableArray *updatedFilters = [self.localFilters mutableCopy];
                NSMutableDictionary *updatedFilter = [filterInfo mutableCopy];
                updatedFilter[@"isDownloaded"] = @YES;
                updatedFilter[@"path"] = localPath;
                updatedFilter[@"localPath"] = localPath;
                updatedFilter[@"previewPath"] = localPath;  // Set preview path for loading preview
                updatedFilter[@"hasPreview"] = @YES;
                updatedFilters[indexPath.item] = updatedFilter;
                self.localFilters = [updatedFilters copy];
                
                // Also update in the organized filters arrays
                [self updateFilterAsDownloaded:filterName withPath:localPath];
                
                // [self.filterCarouselView reloadItemsAtIndexPaths:@[indexPath]]; // Removed
                [self applySelectedNosmaiFilterWithPath:localPath name:filterName];
            } else {
                NSLog(@"❌ Download failed: %@", error.localizedDescription);
                // [self.filterCarouselView reloadItemsAtIndexPaths:@[indexPath]]; // Removed
                [self showSDKError:error];
            }
        });
    }];
}



#pragma mark - UICollectionViewDataSource & Delegate
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView == self.bottomSheetCollectionView) {
        return self.bottomSheetDataSource.count;
    } else if (collectionView == self.beautyFiltersCollectionView) {
        return self.beautyFilters.count;
    }
    return 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView == self.beautyFiltersCollectionView) {
        BeautyFilterCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"BeautyFilterCell" forIndexPath:indexPath];
        BeautyFilterModel *filter = self.beautyFilters[indexPath.item];
        [cell configureWithFilter:filter];
        return cell;
    } else if (collectionView == self.bottomSheetCollectionView) {
        FilterCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kFilterCellIdentifier forIndexPath:indexPath];
        NSDictionary *filterInfo = self.bottomSheetDataSource[indexPath.item];
        
        // Check cache first before clearing image
        NSString *cacheKey = filterInfo[@"name"] ?: [NSString stringWithFormat:@"index_%ld", (long)indexPath.item];
        UIImage *cachedImage = imageCache[cacheKey];
        
        if (cachedImage) {
            // Use cached image immediately
            cell.previewImageView.image = cachedImage;
        } else {
            // Clear image and load if not cached
            cell.previewImageView.image = nil;
            
            // Load image on demand
            if (filterInfo[@"previewPath"]) {
                NSString *previewPath = filterInfo[@"previewPath"];
                
                // Load image asynchronously
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    @autoreleasepool {
                        UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:previewPath];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Cache the loaded image
                            if (previewImage) {
                                imageCache[cacheKey] = previewImage;
                            }
                            
                            // Check if cell is still visible
                            FilterCollectionViewCell *visibleCell = (FilterCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
                            if (visibleCell && previewImage) {
                                visibleCell.previewImageView.image = previewImage;
                            }
                        });
                    }
                });
            } else if (filterInfo[@"thumbnailUrl"] && [filterInfo[@"type"] isEqualToString:@"cloud"]) {
            // For cloud filters without local preview, load from thumbnail URL
            NSString *thumbnailUrl = filterInfo[@"thumbnailUrl"];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                @autoreleasepool {
                    NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:thumbnailUrl]];
                    UIImage *previewImage = imageData ? [UIImage imageWithData:imageData] : nil;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Cache the loaded thumbnail
                        if (previewImage) {
                            imageCache[cacheKey] = previewImage;
                        }
                        
                        // Check if cell is still visible
                        FilterCollectionViewCell *visibleCell = (FilterCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
                        if (visibleCell && previewImage) {
                            visibleCell.previewImageView.image = previewImage;
                        }
                    });
                }
            });
            }
        }
        
        // Check if this filter is currently applied
        BOOL isSelected = [self.currentAppliedFilterName isEqualToString:filterInfo[@"name"]];
        
        // Configure cell with filter info and selection state
        [cell configureWithFilterInfo:filterInfo isDownloading:[self.downloadingFilters[filterInfo[@"name"]] boolValue] isSelected:isSelected];
        return cell;
    }
    
    // Return empty cell for any other collection view
    return [[UICollectionViewCell alloc] init];
}


#pragma mark - UITableViewDataSource & Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {

    
    if (collectionView == self.beautyFiltersCollectionView) {
        // Handle beauty filter selection
        BeautyFilterModel *selectedFilter = self.beautyFilters[indexPath.item];
        
        if (selectedFilter.type == BeautyFilterTypeSlider) {
            // If filter is already active and user taps again, remove it
            if (selectedFilter.isActive && self.currentSliderFilter == selectedFilter) {
                // Remove the filter
                selectedFilter.currentValue = selectedFilter.defaultValue;
                selectedFilter.isActive = NO;
                [self.activeBeautyFilters removeObjectForKey:selectedFilter.identifier];
                
                // Remove from SDK with special handling
                if ([selectedFilter.identifier isEqualToString:@"lipstick"]) {
                    [[NosmaiCore shared].effects removeBuiltInFilterByName:@"LipstickFilter"];
                } else if ([selectedFilter.identifier isEqualToString:@"blusher"]) {
                    [[NosmaiCore shared].effects removeBuiltInFilterByName:@"BlusherFilter"];
                } else if ([selectedFilter.identifier hasPrefix:@"red_channel"] || [selectedFilter.identifier hasPrefix:@"green_channel"] || [selectedFilter.identifier hasPrefix:@"blue_channel"]) {
                    // For RGB filters, check if all channels will be at default after removing this one
                    BeautyFilterModel *redFilter = self.activeBeautyFilters[@"red_channel"];
                    BeautyFilterModel *greenFilter = self.activeBeautyFilters[@"green_channel"];
                    BeautyFilterModel *blueFilter = self.activeBeautyFilters[@"blue_channel"];
                    
                    // Since we just removed the current filter from activeBeautyFilters above,
                    // if no other RGB channels are active, remove the RGB filter entirely
                    if ((!redFilter || redFilter == selectedFilter) &&
                        (!greenFilter || greenFilter == selectedFilter) &&
                        (!blueFilter || blueFilter == selectedFilter)) {
                        [[NosmaiCore shared].effects removeBuiltInFilterByName:@"RGBFilter"];
                    } else {
                        // Otherwise, reapply with remaining channels at their values
                        float red = (redFilter && redFilter != selectedFilter) ? redFilter.currentValue : 1.0f;
                        float green = (greenFilter && greenFilter != selectedFilter) ? greenFilter.currentValue : 1.0f;
                        float blue = (blueFilter && blueFilter != selectedFilter) ? blueFilter.currentValue : 1.0f;
                        [[NosmaiCore shared].effects applyRGBFilterWithRed:red green:green blue:blue];
                    }
                } else {
                    NSString *filterName = [self getFilterNameForIdentifier:selectedFilter.identifier];
                    [[NosmaiCore shared].effects removeBuiltInFilterByName:filterName];
                }
                
                // Hide slider
                [self hideSlider];
                
                // Reload to update UI
                [self.beautyFiltersCollectionView reloadData];
            } else {
                // Show slider for this filter
                [self showSliderForFilter:selectedFilter];
            }
        } else if (selectedFilter.type == BeautyFilterTypeToggle) {
            // Toggle the filter
            [self applyBeautyFilter:selectedFilter];
        }
        
        // Haptic feedback
        [self.hapticGenerator impactOccurred];
        
    } else if (collectionView == self.bottomSheetCollectionView) {
        // Handle bottom sheet selection
        if (indexPath.item >= self.bottomSheetDataSource.count) {
            NSLog(@"❌ Invalid index path for bottom sheet: %ld", (long)indexPath.item);
            return;
        }
        
        NSDictionary *selectedFilterInfo = self.bottomSheetDataSource[indexPath.item];
        NSLog(@"📱 Bottom sheet filter selected: %@", selectedFilterInfo[@"displayName"] ?: selectedFilterInfo[@"name"]);
        
        // Check if this is a cloud filter that needs downloading
        BOOL isCloudFilter = [selectedFilterInfo[@"type"] isEqualToString:@"cloud"];
        BOOL isDownloaded = [selectedFilterInfo[@"isDownloaded"] boolValue];
        
        if (isCloudFilter && !isDownloaded) {
            // Don't dismiss sheet for cloud filters that need downloading
            NSLog(@"☁️ Cloud filter needs download, keeping sheet open");
            [self applyFilterDirectly:selectedFilterInfo];
        } else {
            // Keep sheet open for downloaded/local filters as well
            NSLog(@"📁 Local/downloaded filter selected, keeping sheet open");
            [self applyFilterDirectly:selectedFilterInfo];
        }
        
    }
}

- (void)applyFilterDirectly:(NSDictionary *)filterInfo {
    if (!filterInfo) {
        NSLog(@"❌ No filter info provided");
        return;
    }
    
    NSString *filterType = filterInfo[@"type"] ?: filterInfo[@"filterType"];
    NSString *filterPath = filterInfo[@"path"];
    NSString *filterName = filterInfo[@"name"] ?: filterInfo[@"displayName"];
    BOOL isDownloaded = [filterInfo[@"isDownloaded"] boolValue];
    
    // Special case for clear filter
    if ([filterType isEqualToString:@"special"]) {
        NSLog(@"🧹 Clear filter selected - removing all effects");
        [[NosmaiCore shared].effects removeAllEffects];
        self.currentAppliedFilterName = nil; // Clear current filter tracking
        self.currentAppliedEffectInfo = nil; // Clear current effect tracking
        [self updateEffectsButtonWithEffect:nil]; // Reset effects button to default icon
        [self.hapticGenerator impactOccurred];
        
        // Update selection highlighting without full reload
        if (self.bottomSheetView.superview) {
            // Find all visible cells and update their selection state
            for (NSIndexPath *visibleIndexPath in self.bottomSheetCollectionView.indexPathsForVisibleItems) {
                FilterCollectionViewCell *cell = (FilterCollectionViewCell *)[self.bottomSheetCollectionView cellForItemAtIndexPath:visibleIndexPath];
                if (cell && visibleIndexPath.item < self.bottomSheetDataSource.count) {
                    NSDictionary *cellFilterInfo = self.bottomSheetDataSource[visibleIndexPath.item];
                    BOOL isCellSelected = [self.currentAppliedFilterName isEqualToString:cellFilterInfo[@"name"]];
                    
                    // Update only the selection highlighting without affecting preview images
                    if (isCellSelected) {
                        cell.previewImageView.layer.borderColor = [UIColor systemBlueColor].CGColor;
                        cell.previewImageView.layer.borderWidth = 3.0f;
                    } else {
                        cell.previewImageView.layer.borderColor = [UIColor clearColor].CGColor;
                        cell.previewImageView.layer.borderWidth = 0.0f;
                    }
                }
            }
        }
        return;
    }
    
    // Check if same filter is already applied
    if (self.currentAppliedFilterName && [self.currentAppliedFilterName isEqualToString:filterName]) {
        NSLog(@"⚠️ Filter '%@' is already applied, skipping duplicate application", filterName);
        return;
    }
    
    [self.hapticGenerator impactOccurred];
    
    
    
 
    if ([filterInfo[@"type"] isEqualToString:@"cloud"] && !isDownloaded) {
        NSLog(@"☁️ Cloud filter needs downloading");
        NSString *filterId = filterInfo[@"filterId"];
        if (filterId) {
            [self downloadAndApplyCloudFilter:filterInfo];
        } else {
            NSLog(@"❌ No filterId for cloud filter");
        }
        return;
    }
    
    // Apply the filter
    if (filterPath && filterPath.length > 0) {
        // Clear previous filter tracking before applying new one
        self.currentAppliedFilterName = nil;
        
        [[NosmaiCore shared].effects applyEffect:filterPath completion:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    NSLog(@"✅ Filter applied successfully!");
                    // Set current applied filter name for tracking
                    self.currentAppliedFilterName = filterName;
                    
                    // Update selection highlighting without full reload
                    if (self.bottomSheetView.superview) {
                        // Find all visible cells and update their selection state
                        for (NSIndexPath *visibleIndexPath in self.bottomSheetCollectionView.indexPathsForVisibleItems) {
                            FilterCollectionViewCell *cell = (FilterCollectionViewCell *)[self.bottomSheetCollectionView cellForItemAtIndexPath:visibleIndexPath];
                            if (cell && visibleIndexPath.item < self.bottomSheetDataSource.count) {
                                NSDictionary *cellFilterInfo = self.bottomSheetDataSource[visibleIndexPath.item];
                                BOOL isCellSelected = [self.currentAppliedFilterName isEqualToString:cellFilterInfo[@"name"]];
                                
                                // Update only the selection highlighting without affecting preview images
                                if (isCellSelected) {
                                    cell.previewImageView.layer.borderColor = [UIColor systemBlueColor].CGColor;
                                    cell.previewImageView.layer.borderWidth = 3.0f;
                                } else {
                                    cell.previewImageView.layer.borderColor = [UIColor clearColor].CGColor;
                                    cell.previewImageView.layer.borderWidth = 0.0f;
                                }
                            }
                        }
                    }
                    
                    // Check if this filter is an effect by searching in effects array
                    BOOL isEffect = NO;
                    if (self.onlyEffectsArray) {
                        for (NSDictionary *effect in self.onlyEffectsArray) {
                            if ([effect[@"name"] isEqualToString:filterName]) {
                                isEffect = YES;
                                break;
                            }
                        }
                    }
                    
                    // Update effects button preview if this is an effect
                    if (isEffect) {
                        self.currentAppliedEffectInfo = filterInfo;
                        [self updateEffectsButtonWithEffect:filterInfo];
                        NSLog(@"🎭 Effect applied, updating button preview for: %@", filterName);
                    } else {
                        // Clear effect preview if applying a regular filter
                        self.currentAppliedEffectInfo = nil;
                        [self updateEffectsButtonWithEffect:nil];
                        NSLog(@"🎨 Filter applied, resetting button to default icon");
                    }
                } else {
                    NSLog(@"❌ Failed to apply filter: %@", error.localizedDescription);
                }
            });
        }];
    } else {
        NSLog(@"❌ No filter path available for: %@", filterName);
    }
}



- (void)downloadAndApplyCloudFilter:(NSDictionary *)filterInfo {
    NSString *filterId = filterInfo[@"filterId"];
    NSString *filterName = filterInfo[@"name"] ?: filterInfo[@"displayName"];
    
    if (!filterId) {
        NSLog(@"❌ No filterId for cloud filter: %@", filterName);
        return;
    }
    
    // Check if same filter is already applied
    if (self.currentAppliedFilterName && [self.currentAppliedFilterName isEqualToString:filterName]) {
        NSLog(@"⚠️ Cloud filter '%@' is already applied, skipping duplicate application", filterName);
        return;
    }
    
    // Check if already downloading to prevent duplicate downloads
    if ([self.downloadingFilters[filterName] boolValue]) {
        NSLog(@"⏳ Filter %@ already downloading, skipping duplicate request", filterName);
        return;
    }
    
    self.downloadingFilters[filterName] = @YES;
    
    // Update only the specific downloading cell instead of full reload
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.bottomSheetView.superview) {
            // Find the index of the downloading filter
            NSInteger downloadingIndex = [self.bottomSheetDataSource indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
                return [obj[@"name"] isEqualToString:filterName];
            }];
            
            if (downloadingIndex != NSNotFound) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:downloadingIndex inSection:0];
                // Update only the download UI without reloading the entire cell
                FilterCollectionViewCell *cell = (FilterCollectionViewCell *)[self.bottomSheetCollectionView cellForItemAtIndexPath:indexPath];
                if (cell) {
                    // Show download UI directly without affecting preview image
                    cell.downloadIcon.hidden = YES;
                    cell.downloadProgress.hidden = NO;
                    cell.downloadProgress.progress = 0.0;
                    [cell.progressIndicator startAnimating];
                    NSLog(@"🔄 Updated download UI for cell at index: %ld", (long)downloadingIndex);
                }
            }
        }
    });
    
    // Show immediate feedback
    dispatch_async(dispatch_get_main_queue(), ^{
        // Haptic feedback for download start
        [self.hapticGenerator impactOccurred];
        
        // Show a toast notification
        [self showDownloadStartedToastForFilter:filterName];
    });
    
    [[NosmaiCore shared].effects downloadCloudFilter:filterId progress:^(float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update progress in bottom sheet cells
            if (self.bottomSheetView.superview) {
                NSArray *visibleCells = [self.bottomSheetCollectionView visibleCells];
                for (FilterCollectionViewCell *cell in visibleCells) {
                    NSIndexPath *indexPath = [self.bottomSheetCollectionView indexPathForCell:cell];
                    if (indexPath && indexPath.item < self.bottomSheetDataSource.count) {
                        NSDictionary *cellFilterInfo = self.bottomSheetDataSource[indexPath.item];
                        if ([cellFilterInfo[@"name"] isEqualToString:filterName]) {
                            [cell updateDownloadProgress:progress];
                            break;
                        }
                    }
                }
            }
        });
    } completion:^(BOOL success, NSString *localPath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.downloadingFilters removeObjectForKey:filterName];
            if (success && localPath) {
//                NSLog(@"✅ Cloud filter downloaded to: %@", localPath);
                
                // Success haptic feedback
                UINotificationFeedbackGenerator *feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
                [feedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];
                
                // Show success toast
                [self showDownloadCompletedToastForFilter:filterName success:YES];
                
                // Apply the downloaded filter
                [[NosmaiCore shared].effects removeAllEffects];
                
                // Clear previous filter tracking before applying new one
                self.currentAppliedFilterName = nil;
                
                [[NosmaiCore shared].effects applyEffect:localPath completion:^(BOOL applySuccess, NSError *applyError) {
                    if (applySuccess) {
                        NSLog(@"✅ Downloaded filter applied successfully!");
                        // Set current applied filter name for tracking
                        self.currentAppliedFilterName = filterName;
                        
                        // Update selection highlighting without full reload
                        if (self.bottomSheetView.superview) {
                            // Find all visible cells and update their selection state
                            for (NSIndexPath *visibleIndexPath in self.bottomSheetCollectionView.indexPathsForVisibleItems) {
                                FilterCollectionViewCell *cell = (FilterCollectionViewCell *)[self.bottomSheetCollectionView cellForItemAtIndexPath:visibleIndexPath];
                                if (cell && visibleIndexPath.item < self.bottomSheetDataSource.count) {
                                    NSDictionary *cellFilterInfo = self.bottomSheetDataSource[visibleIndexPath.item];
                                    BOOL isCellSelected = [self.currentAppliedFilterName isEqualToString:cellFilterInfo[@"name"]];
                                    
                                    // Update only the selection highlighting without affecting preview images
                                    if (isCellSelected) {
                                        cell.previewImageView.layer.borderColor = [UIColor systemBlueColor].CGColor;
                                        cell.previewImageView.layer.borderWidth = 3.0f;
                                    } else {
                                        cell.previewImageView.layer.borderColor = [UIColor clearColor].CGColor;
                                        cell.previewImageView.layer.borderWidth = 0.0f;
                                    }
                                }
                            }
                        }
                        
                        // Check if this downloaded filter is an effect
                        BOOL isEffect = NO;
                        if (self.onlyEffectsArray) {
                            for (NSDictionary *effect in self.onlyEffectsArray) {
                                if ([effect[@"name"] isEqualToString:filterName]) {
                                    isEffect = YES;
                                    break;
                                }
                            }
                        }
                        
                        // Update effects button preview if this is an effect
                        if (isEffect) {
                            // Create updated filter info with local path for preview
                            NSMutableDictionary *updatedFilterInfo = [filterInfo mutableCopy];
                            updatedFilterInfo[@"previewPath"] = localPath;
                            self.currentAppliedEffectInfo = [updatedFilterInfo copy];
                            [self updateEffectsButtonWithEffect:self.currentAppliedEffectInfo];
                            NSLog(@"🎭 Downloaded effect applied, updating button preview for: %@", filterName);
                        } else {
                            // Clear effect preview if applying a regular filter
                            self.currentAppliedEffectInfo = nil;
                            [self updateEffectsButtonWithEffect:nil];
                            NSLog(@"🎨 Downloaded filter applied, resetting button to default icon");
                        }
                    } else {
                        NSLog(@"❌ Failed to apply downloaded filter: %@", applyError.localizedDescription);
                    }
                }];
                
                // Update the filter info to mark it as downloaded
                [self updateFilterAsDownloaded:filterName withPath:localPath];
                
                // Refresh bottomSheetDataSource to reflect the updated arrays
                if (self.bottomSheetView.superview) {
                    if ([self.currentBottomSheetType isEqualToString:@"Filters"]) {
                        self.bottomSheetDataSource = self.onlyFiltersArray;
                    } else if ([self.currentBottomSheetType isEqualToString:@"Effects"]) {
                        self.bottomSheetDataSource = self.onlyEffectsArray;
                    }
                    
                    // Update only the specific downloaded cell instead of full reload
                    NSInteger downloadedIndex = [self.bottomSheetDataSource indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
                        return [obj[@"name"] isEqualToString:filterName];
                    }];
                    
                    if (downloadedIndex != NSNotFound) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:downloadedIndex inSection:0];
                        // Selective update for downloaded filter - only reload the specific cell
                        [self.bottomSheetCollectionView reloadItemsAtIndexPaths:@[indexPath]];
                        NSLog(@"✅ Selective reload for downloaded filter at index: %ld", (long)downloadedIndex);
                    } else {
                        NSLog(@"⚠️ Downloaded filter not found in data source, doing full reload");
                        [self.bottomSheetCollectionView reloadData];
                    }
                }
                
                // Keep sheet open after successful download and application
                NSLog(@"✅ Download and application completed, keeping sheet open");
            } else {
                NSLog(@"❌ Download failed: %@", error.localizedDescription);
                
                // Error haptic feedback
                UINotificationFeedbackGenerator *feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
                [feedbackGenerator notificationOccurred:UINotificationFeedbackTypeError];
                
                // Show failure toast
                [self showDownloadCompletedToastForFilter:filterName success:NO];
                
                // Update only the specific failed download cell instead of full reload
                if (self.bottomSheetView.superview) {
                    NSInteger failedIndex = [self.bottomSheetDataSource indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
                        return [obj[@"name"] isEqualToString:filterName];
                    }];
                    
                    if (failedIndex != NSNotFound) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:failedIndex inSection:0];
                        [self.bottomSheetCollectionView reloadItemsAtIndexPaths:@[indexPath]];
                        NSLog(@"❌ Reloading only failed download cell at index: %ld", (long)failedIndex);
                    } else {
                        NSLog(@"⚠️ Failed download filter not found in data source, doing full reload");
                        [self.bottomSheetCollectionView reloadData];
                    }
                }
            }
        });
    }];
}

- (void)updateFilterAsDownloaded:(NSString *)filterName withPath:(NSString *)path {
    // Update in all arrays
    NSMutableArray *arrays = @[
        [self.localFilters mutableCopy],
        [self.onlyFiltersArray mutableCopy],
        [self.onlyEffectsArray mutableCopy]
    ];
    
    for (NSMutableArray *array in arrays) {
        for (int i = 0; i < array.count; i++) {
            NSMutableDictionary *filter = [array[i] mutableCopy];
            if ([filter[@"name"] isEqualToString:filterName]) {
                filter[@"isDownloaded"] = @YES;
                filter[@"isDownloading"] = @NO;  // Remove downloading state
                filter[@"path"] = path;
                filter[@"localPath"] = path;
                filter[@"previewPath"] = path;  // Set preview path for loading preview
                filter[@"hasPreview"] = @YES;
                array[i] = [filter copy];
            }
        }
    }
    
    // Update the properties
    self.localFilters = arrays[0];
    self.onlyFiltersArray = arrays[1];
    self.onlyEffectsArray = arrays[2];
    
    // Reload collection views to show updated previews
    dispatch_async(dispatch_get_main_queue(), ^{
        // Reload main carousel
        // [self.filterCarouselView reloadData]; // Removed - filterCarouselView no longer exists
        
        // If bottom sheet is visible, reload it too
        if (self.bottomSheetView.superview) {
            [self.bottomSheetCollectionView reloadData];
        }
    });
}








#pragma mark - Actions (Recording, Camera Switch, etc.)

- (void)closeController {
    if (self.isRecording) {
        [self stopRecording];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performCloseController];
        });
    } else {
        [self performCloseController];
    }
}

- (void)performCloseController {
    if ([NosmaiCore shared].camera.isCapturing) {
        [[NosmaiCore shared].camera stopCapture];
    }
    [[NosmaiCore shared] cleanup];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)switchCamera {
    if (!self.isSDKReady) return;
    
    [self animateButton:self.cameraSwitchButton];
    [[NosmaiCore shared].camera switchCamera];
}


- (void)recordButtonTapped {
    if (!self.isSDKReady) return;
    
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    
    if (self.isRecording) {
        [self stopRecording];
    } else {
        [self startRecording];
    }
}



- (void)startRecording {
    // Hide preview box if visible
    if (!self.videoPreviewContainer.hidden) {
        [UIView animateWithDuration:0.2 animations:^{
            self.videoPreviewContainer.alpha = 0;
            self.videoPreviewContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        } completion:^(BOOL finished) {
            self.videoPreviewContainer.hidden = YES;
            self.videoPreviewContainer.transform = CGAffineTransformIdentity;
        }];
    }
    
    self.isRecording = YES;
    self.recordingStartTime = [NSDate timeIntervalSinceReferenceDate];
    
    // Start the SDK recording
    [[NosmaiCore shared] startRecordingWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"Failed to start recording: %@", error);
                [self stopRecording]; // Revert UI if recording fails
            });
        }
    }];
    
    // Animate to recording state
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        // Scale down inner circle and make it a rounded square
        self.recordButtonInnerCircle.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self.recordButtonInnerCircle.layer.cornerRadius = 8;
        
        // Change outer ring color
        self.recordButtonOuterRing.layer.borderColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.8].CGColor;
    } completion:^(BOOL finished) {
        // Start pulsing animation
        [self startPulsingAnimation];
        
        // Show time label
        self.recordingTimeLabel.hidden = NO;
        self.recordingTimeLabel.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{
            self.recordingTimeLabel.alpha = 1;
        }];
        
        // Start timer
        [self startRecordingTimer];
    }];
    
    // Add progress layer
    [self setupProgressLayer];
}

- (void)stopRecording {
    self.isRecording = NO;
    
    // ⚡ IMMEDIATELY show full-screen loader
    [self showFullScreenLoader];
    
    // Stop timer
    [self.recordingTimer invalidate];
    self.recordingTimer = nil;
    
    // Stop the SDK recording
    [[NosmaiCore shared] stopRecordingWithCompletion:^(NSURL *videoURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Hide the full-screen loader
            [self hideFullScreenLoader];
            
            if (videoURL && !error) {
                NSLog(@"Recording finished successfully: %@", videoURL);
                [self showRecordingSuccessWithVideoURL:videoURL];
            } else if (error) {
                NSLog(@"Error stopping recording: %@", error);
                [self showRecordingError:error];
            }
        });
    }];
    
    // Remove pulsing animation
    [self stopPulsingAnimation];
    
    // Remove progress layer
    [self.progressLayer removeFromSuperlayer];
    
    // Hide time label
    [UIView animateWithDuration:0.2 animations:^{
        self.recordingTimeLabel.alpha = 0;
    } completion:^(BOOL finished) {
        self.recordingTimeLabel.hidden = YES;
        self.recordingTimeLabel.text = @"00:00";
    }];
    
    // Animate back to idle state
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut animations:^{
        // Scale back to normal
        self.recordButtonInnerCircle.transform = CGAffineTransformIdentity;
        self.recordButtonInnerCircle.layer.cornerRadius = 30;
        
        // Reset outer ring color
        self.recordButtonOuterRing.layer.borderColor = [UIColor whiteColor].CGColor;
    } completion:nil];
}



- (void)startPulsingAnimation {
    CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scaleAnimation.fromValue = @1.0;
    scaleAnimation.toValue = @1.1;
    scaleAnimation.duration = 0.8;
    scaleAnimation.autoreverses = YES;
    scaleAnimation.repeatCount = HUGE_VALF;
    scaleAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.recordButtonOuterRing.layer addAnimation:scaleAnimation forKey:@"pulse"];
    
    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.fromValue = @1.0;
    opacityAnimation.toValue = @0.6;
    opacityAnimation.duration = 0.8;
    opacityAnimation.autoreverses = YES;
    opacityAnimation.repeatCount = HUGE_VALF;
    opacityAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.recordButtonOuterRing.layer addAnimation:opacityAnimation forKey:@"opacity"];
}

- (void)stopPulsingAnimation {
    [self.recordButtonOuterRing.layer removeAllAnimations];
}


- (void)topLeftButtonPressed {
    [[NosmaiCore shared] capturePhoto:^(UIImage *image, NSError *error) {
        if (image) {
            [self showPhotoSuccessWithImage:image];
        } else {
            // Handle error
        }
    }];
}

- (void)setupProgressLayer {
    CGFloat radius = 38;
    UIBezierPath *circlePath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(40, 40)
                                                              radius:radius
                                                          startAngle:-M_PI_2
                                                            endAngle:3 * M_PI_2
                                                           clockwise:YES];
    
    self.progressLayer.path = circlePath.CGPath;
    self.progressLayer.frame = self.recordButtonOuterRing.bounds;
    [self.recordButtonOuterRing.layer addSublayer:self.progressLayer];
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = @0.0;
    animation.toValue = @1.0;
    animation.duration = 60.0; // 60 second max recording
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    [self.progressLayer addAnimation:animation forKey:@"progress"];
}

- (void)startRecordingTimer {
    self.recordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateRecordingTime) userInfo:nil repeats:YES];
}


- (void)updateRecordingTime {
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsedTime = currentTime - self.recordingStartTime;
    
    NSInteger minutes = (NSInteger)elapsedTime / 60;
    NSInteger seconds = (NSInteger)elapsedTime % 60;
    
    self.recordingTimeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
    
    // Stop recording after max duration (60 seconds)
    if (elapsedTime >= 60.0) {
        [self stopRecording];
    }
}

- (void)showRecordingSuccessWithVideoURL:(NSURL *)videoURL {
    // Store the video URL
    self.lastRecordedVideoURL = videoURL;
    
    // Add success haptic feedback
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    
    // Generate thumbnail from video
    [self generateThumbnailFromVideo:videoURL];
    
    // Show the preview box with animation
    [self showVideoPreviewBoxAnimated];
    
    // Save to photos
    [self saveVideoToPhotos:videoURL];
    
    // Show saving indicator
    [self showSavingIndicator];
}


// Generate thumbnail from video
- (void)generateThumbnailFromVideo:(NSURL *)videoURL {
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMake(1, 1);
    NSError *error = nil;
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:&error];
    
    if (imageRef) {
        UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.videoThumbnailView.image = thumbnail;
        });
    }
}

- (void)showVideoPreviewBoxAnimated {
    self.videoPreviewContainer.hidden = NO;
    self.videoPreviewContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
    
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.videoPreviewContainer.alpha = 1.0;
        self.videoPreviewContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
}


- (void)playPreviewVideo {
    if (!self.lastRecordedVideoURL) return;
    
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
    
    // Create and present video player
    AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
    playerViewController.player = [AVPlayer playerWithURL:self.lastRecordedVideoURL];
    playerViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    playerViewController.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self presentViewController:playerViewController animated:YES completion:^{
        [playerViewController.player play];
    }];
}


- (void)showSavingIndicator {
    // Create a toast-style notification
    UIView *toastView = [[UIView alloc] init];
    toastView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    toastView.layer.cornerRadius = 25;
    toastView.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *label = [[UILabel alloc] init];
    label.text = @"Saving video...";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    
    [toastView addSubview:label];
    [toastView addSubview:spinner];
    [self.view addSubview:toastView];
    
    [NSLayoutConstraint activateConstraints:@[
        [toastView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toastView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:80],
        [toastView.heightAnchor constraintEqualToConstant:50],
        
        [spinner.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
        [spinner.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
        
        [label.leadingAnchor constraintEqualToAnchor:spinner.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:toastView.trailingAnchor constant:-15],
        [label.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
    ]];
    
    // Animate in
    toastView.alpha = 0;
    toastView.transform = CGAffineTransformMakeTranslation(0, -20);
    [UIView animateWithDuration:0.3 animations:^{
        toastView.alpha = 1;
        toastView.transform = CGAffineTransformIdentity;
    }];
    
    // Store reference to update later
    toastView.tag = 999;
}





#pragma mark - Alerts and Save Handlers
- (void)showSDKNotReadyAlert:(NSString *)message {
    // Create a temporary toast-style alert that doesn't interrupt the user
    UILabel *toastLabel = [[UILabel alloc] init];
    toastLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.textAlignment = NSTextAlignmentCenter;
    toastLabel.font = [UIFont systemFontOfSize:14.0];
    toastLabel.text = message;
    toastLabel.layer.cornerRadius = 20.0;
    toastLabel.clipsToBounds = YES;
    toastLabel.alpha = 0.0;
    
    // Calculate size and position
    CGSize textSize = [message sizeWithAttributes:@{NSFontAttributeName: toastLabel.font}];
    CGFloat width = textSize.width + 40;
    CGFloat height = 40;
    toastLabel.frame = CGRectMake((self.view.frame.size.width - width) / 2,
                                 self.view.frame.size.height * 0.75,
                                 width, height);
    
    [self.view addSubview:toastLabel];
    
    // Animate in, hold, then fade out
    [UIView animateWithDuration:0.3 animations:^{
        toastLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{
            toastLabel.alpha = 0.0;
        } completion:^(BOOL finished) {
            [toastLabel removeFromSuperview];
        }];
    }];
}

- (void)showRecordingError:(NSError *)error {
    [self showAlertWithTitle:@"Recording Error" message:error.localizedDescription];
}

- (void)showRecordingSuccessWithPath:(NSString *)filePath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Recording Complete" message:[NSString stringWithFormat:@"Video saved to: %@", filePath] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save to Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self saveVideoToPhotos:[NSURL fileURLWithPath:filePath]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showPhotoSuccessWithImage:(UIImage *)image {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Photo Captured" message:@"Photo capture was successful." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save to Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self saveImageToPhotos:image];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveVideoToPhotos:(NSURL *)videoURL {
    // First check if we have permission to save to photo library
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            // Use PHPhotoLibrary for better reliability
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
                request.creationDate = [NSDate date];
            } completionHandler:^(BOOL success, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [self video:videoURL.path didFinishSavingWithError:nil contextInfo:nil];
                    } else {
                        [self video:videoURL.path didFinishSavingWithError:error contextInfo:nil];
                    }
                });
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"PhotoLibrary"
                                                     code:401
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Photo library access denied"}];
                [self video:videoURL.path didFinishSavingWithError:error contextInfo:nil];
            });
        }
    }];
}


- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    UIView *toastView = [self.view viewWithTag:999];
    
    if (error) {
        // Update toast to show error
        if (toastView) {
            for (UIView *subview in toastView.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    [(UILabel *)subview setText:@"Failed to save video"];
                }
                if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
                    [(UIActivityIndicatorView *)subview stopAnimating];
                    [subview removeFromSuperview];
                }
            }
            
            // Add error icon
            UIImageView *errorIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]];
            errorIcon.tintColor = [UIColor redColor];
            errorIcon.translatesAutoresizingMaskIntoConstraints = NO;
            [toastView addSubview:errorIcon];
            
            [NSLayoutConstraint activateConstraints:@[
                [errorIcon.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
                [errorIcon.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
                [errorIcon.widthAnchor constraintEqualToConstant:24],
                [errorIcon.heightAnchor constraintEqualToConstant:24],
            ]];
        }
        
        NSLog(@"Error saving video: %@", error.localizedDescription);
    } else {
        // Update toast to show success
        if (toastView) {
            for (UIView *subview in toastView.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    [(UILabel *)subview setText:@"Video saved to Photos!"];
                }
                if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
                    [(UIActivityIndicatorView *)subview stopAnimating];
                    [subview removeFromSuperview];
                }
            }
            
            // Add checkmark icon
            UIImageView *checkIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
            checkIcon.tintColor = [UIColor greenColor];
            checkIcon.translatesAutoresizingMaskIntoConstraints = NO;
            [toastView addSubview:checkIcon];
            
            [NSLayoutConstraint activateConstraints:@[
                [checkIcon.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
                [checkIcon.centerYAnchor constraintEqualToAnchor:toastView.centerYAnchor],
                [checkIcon.widthAnchor constraintEqualToConstant:24],
                [checkIcon.heightAnchor constraintEqualToConstant:24],
            ]];
        }
    }
    
    // Animate out after delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (toastView) {
            [UIView animateWithDuration:0.3 animations:^{
                toastView.alpha = 0;
                toastView.transform = CGAffineTransformMakeTranslation(0, -20);
            } completion:^(BOOL finished) {
                [toastView removeFromSuperview];
            }];
        }
    });
}

- (void)saveImageToPhotos:(UIImage *)image {
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        [self showAlertWithTitle:@"Save Failed" message:@"Could not save photo. Check permissions."];
    } else {
        [self showAlertWithTitle:@"Success" message:@"Photo saved to Photos!"];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark - NosmaiDelegate Methods

- (void)nosmaiDidFailWithError:(NSError *)error {
    NSLog(@"❌ Nosmai Core Error: %@", error.localizedDescription);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showSDKError:error];
    });
}

- (void)nosmaiDidChangeState:(NosmaiState)newState {}
- (void)nosmaiCameraDidChangeState:(NosmaiCameraState)newState {}
- (void)nosmaiCameraDidFailWithError:(NSError *)error {}
- (void)nosmaiCameraDidCaptureFrame {}
- (void)nosmaiEffectDidChangeState:(NosmaiEffectState)newState forEffect:(NSString *)effectID {}
- (void)nosmaiEffectDidFailWithError:(NSError *)error forEffect:(NSString *)effectID {}

- (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {

    
    // Process the updated filters
    [self processOrganizedFilters:organizedFilters];
    
    // Hide cloud filters loading indicator as filters have been loaded
    self.isLoadingCloudFilters = NO;
    if (self.cloudFiltersLoadingView) {
        self.cloudFiltersLoadingView.hidden = YES;
    }
    
    // If bottom sheet is open, update it too
    if (self.bottomSheetView.superview) {
        if ([self.currentBottomSheetType isEqualToString:@"Filters"]) {
            self.bottomSheetDataSource = self.onlyFiltersArray;
        } else if ([self.currentBottomSheetType isEqualToString:@"Effects"]) {
            self.bottomSheetDataSource = self.onlyEffectsArray;
        }
        [self.bottomSheetCollectionView reloadData];
    }
}

@end

