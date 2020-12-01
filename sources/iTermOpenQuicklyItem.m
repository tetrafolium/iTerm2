#import "iTermOpenQuicklyItem.h"
#import "NSImage+iTerm.h"
#import "iTermLogoGenerator.h"
#import "iTermOpenQuicklyTableCellView.h"

@implementation iTermOpenQuicklyItem
@end

@implementation iTermOpenQuicklySessionItem

- (instancetype)init {
  self = [super init];
  if (self) {
    _logoGenerator = [[iTermLogoGenerator alloc] init];
  }
  return self;
}

- (NSImage *)icon {
  return [_logoGenerator generatedImage];
}

@end

@implementation iTermOpenQuicklyProfileItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"new-tab" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyChangeProfileItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"ChangeProfile" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyColorPresetItem

- (instancetype)init {
  self = [super init];
  if (self) {
    _logoGenerator = [[iTermLogoGenerator alloc] init];
  }
  return self;
}

- (NSImage *)icon {
  return [_logoGenerator generatedImage];
}

@end

@implementation iTermOpenQuicklyArrangementItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"restore-arrangement" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyHelpItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"Info" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyScriptItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"ScriptIcon" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyActionItem : iTermOpenQuicklyItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"OpenQuicklyActionIcon" forClass:self.class];
}

@end

@implementation iTermOpenQuicklySnippetItem : iTermOpenQuicklyItem

- (NSImage *)icon {
  return [NSImage it_imageNamed:@"OpenQuicklySnippetIcon" forClass:self.class];
}

// This can be the sender to -sendSnippet:
- (id)representedObject {
  return self.snippet;
}

@end
