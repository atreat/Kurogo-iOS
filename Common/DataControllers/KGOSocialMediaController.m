#import "KGOSocialMediaController.h"
#import "SFHFKeychainUtils.h"
#import "MIT_MobileAppDelegate.h"
#import "JSONAPIRequest.h"

NSString * const KGOSocialMediaTypeFacebook = @"Facebook";
NSString * const KGOSocialMediaTypeTwitter = @"Twitter";
NSString * const KGOSocialMediaTypeEmail = @"Email";
NSString * const KGOSocialMediaTypeBitly = @"bit.ly";

static NSString * const TwitterUsernameKey = @"TwitterUsername";
static NSString * const TwitterServiceName = @"Twitter";

static KGOSocialMediaController *s_controller = nil;

@implementation KGOSocialMediaController

@synthesize twitterDelegate, bitlyDelegate, facebookDelegate;

+ (KGOSocialMediaController *)sharedController {
	if (s_controller == nil) {
		s_controller = [[KGOSocialMediaController alloc] init];
	}
	return s_controller;
}

- (NSArray *)allSupportedSharingTypes {
	return nil;
}

- (BOOL)supportsSharing {
	return [[self allSupportedSharingTypes] count] > 0;
}

- (BOOL)supportsFacebookSharing {
	return [_preferences objectForKey:KGOSocialMediaTypeFacebook] != nil;
}

- (BOOL)supportsTwitterSharing {
	return [_preferences objectForKey:KGOSocialMediaTypeTwitter] != nil;
}

- (BOOL)supportsEmailSharing {
	return [_preferences objectForKey:KGOSocialMediaTypeEmail] != nil;
}

- (id)init {
	if (self = [super init]) {
		NSString * file = [[NSBundle mainBundle] pathForResource:@"Config" ofType:@"plist"];
        NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:file];
		
		_preferences = [[infoDict objectForKey:@"SocialMedia"] retain];
	}
	return self;
}

- (void)dealloc {
	[self shutdownTwitter];
	[self shutdownFacebook];
	[self shutdownBitly];
	
	[_preferences release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark bit.ly

- (void)getBitlyURLForLongURL:(NSString *)longURL delegate:(id<BitlyWrapperDelegate>)delegate {
	self.bitlyDelegate = delegate;

	NSString *username = [[_preferences objectForKey:KGOSocialMediaTypeBitly] objectForKey:@"Username"];
	NSString *key = [[_preferences objectForKey:KGOSocialMediaTypeBitly] objectForKey:@"APIKey"];

	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] showNetworkActivityIndicator];
	_bitlyConnection = [(ConnectionWrapper *)[ConnectionWrapper alloc] initWithDelegate:self]; // cast because multiple classes implement -initWithDelegate
	NSString *bitlyURLString = [NSString stringWithFormat:@"http://api.bit.ly/v3/shorten"
								"?login=%@"
								"&apiKey=%@"
								"&longURL=%@"
								"&format=json",
								username, key, longURL];
	
	NSURL *url = [NSURL URLWithString:bitlyURLString];
	[_bitlyConnection requestDataFromURL:url];
}

- (void)shutdownBitly {
	if (_bitlyConnection) {
		[_bitlyConnection cancel];
		[_bitlyConnection release];
		_bitlyConnection = nil;
		[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
	}
}

#pragma mark bit.ly - ConnectionWrapper

- (void)connection:(ConnectionWrapper *)wrapper handleData:(NSData *)data {
    id jsonObj = [JSONAPIRequest objectWithJSONData:data];
    if (jsonObj && [jsonObj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *urlData = nil;
        if (urlData = [(NSDictionary *)jsonObj objectForKey:@"data"]) {
            NSString *shortURL = [urlData objectForKey:@"url"];
			[self.bitlyDelegate didGetBitlyURL:shortURL];
        }
    }
    [_bitlyConnection release];
	_bitlyConnection = nil;
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
}

- (BOOL)connection:(ConnectionWrapper *)connection shouldDisplayAlertForError:(NSError *)error {
    return YES;
}

- (void)connection:(ConnectionWrapper *)wrapper handleConnectionFailureWithError:(NSError *)error {
	if (wrapper == _bitlyConnection) {
		[_bitlyConnection release];
		_bitlyConnection = nil;
		if ([self.bitlyDelegate respondsToSelector:@selector(failedToGetBitlyURL)]) {
			[self.bitlyDelegate failedToGetBitlyURL];
		}
	}
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
}

#pragma mark -
#pragma mark Twitter

// these are just standard HTTP response codes,
// but some may be accompanied with an additional message that we may eventually want to distinguish.
// http://apiwiki.twitter.com/w/page/22554652/HTTP-Response-Codes-and-Errors
#define TwitterResponseCodeUnauthorized 401

- (void)startupTwitter {
	if (!_twitterEngine) {
		_twitterEngine = [[MGTwitterEngine alloc] initWithDelegate:self];
		NSString *key = [[_preferences objectForKey:KGOSocialMediaTypeTwitter] objectForKey:@"OAuthConsumerKey"];
		NSString *secret = [[_preferences objectForKey:KGOSocialMediaTypeTwitter] objectForKey:@"OAuthConsumerSecret"];
		[_twitterEngine setConsumerKey:key secret:secret];
	}
}

- (void)shutdownTwitter {
	self.twitterDelegate = nil;
	if (_twitterEngine) {
		for (NSString *identifier in [_twitterEngine connectionIdentifiers]) {
			[_twitterEngine closeConnection:identifier];
			[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
		}
		[_twitterEngine release];
		_twitterEngine = nil;
	}
}

- (void)loginTwitterWithDelegate:(id<TwitterWrapperDelegate>)delegate {
	self.twitterDelegate = delegate;
	[self startupTwitter];
	
	NSString *username = [self twitterUsername];
	if (!username) {
		[self.twitterDelegate promptForTwitterLogin];
		return;
	}
	
	NSError *error = nil;
	NSString *password = [SFHFKeychainUtils getPasswordForUsername:username andServiceName:TwitterServiceName error:&error];
	if (error) {
		NSLog(@"something went wrong looking up access token, error=%@", error);
		[self.twitterDelegate twitterFailedToLogin];
		return;
	}
	
	[_twitterEngine getXAuthAccessTokenForUsername:username password:password];
}

- (void)loginTwitterWithUsername:(NSString *)username password:(NSString *)password {
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] showNetworkActivityIndicator];
	self.twitterUsername = username;
	[_twitterEngine getXAuthAccessTokenForUsername:username password:password];
}

- (void)logoutTwitter {
	NSString *username = [[NSUserDefaults standardUserDefaults] objectForKey:TwitterUsernameKey];
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:TwitterUsernameKey];
	
	NSError *error = nil;
	[SFHFKeychainUtils deleteItemForUsername:username andServiceName:TwitterServiceName error:&error];
	
	if (error) {
		NSLog(@"failed to log out of Twitter: %@", [error description]);
	}
	
	[self.twitterDelegate twitterDidLogout];
}

- (void)postToTwitter:(NSString *)text {
	[_twitterEngine sendUpdate:text];
}

- (NSString *)twitterUsername {
	if (_twitterUsername) {
		return _twitterUsername;
	}
    return [[NSUserDefaults standardUserDefaults] objectForKey:TwitterUsernameKey];
}

- (void)setTwitterUsername:(NSString *)username {
	[_twitterUsername release];
	_twitterUsername = [username retain];
}

#pragma mark Twitter - MGTwitterEngineDelegate

// gets called in response to -[getXAuthAccessTokenForUsername:password:]
- (void)accessTokenReceived:(OAToken *)aToken forRequest:(NSString *)connectionIdentifier {
	NSError *error = nil;
    [_twitterEngine setAccessToken:aToken];
    
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
	
	if (!error) {
		[[NSUserDefaults standardUserDefaults] setObject:_twitterUsername forKey:TwitterUsernameKey];
		[self.twitterDelegate twitterDidLogin];
	} else {
		NSLog(@"error on saving token=%@", [error description]);
	}
}

- (void)requestSucceeded:(NSString *)connectionIdentifier {
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
	[self.twitterDelegate twitterRequestSucceeded:connectionIdentifier];
}

- (void)requestFailed:(NSString *)connectionIdentifier withError:(NSError *)error {
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
	
	NSString *errorTitle;
	NSString *errorMessage;
	
	if (error.code == TwitterResponseCodeUnauthorized) {
		errorTitle = NSLocalizedString(@"Login failed", nil);
		errorMessage = NSLocalizedString(@"Twitter username and password is not recognized", nil);
		
		[self logoutTwitter];
		
	} else {
		errorTitle = NSLocalizedString(@"Network failed", nil);
		errorMessage = NSLocalizedString(@"Failure connecting to Twitter", nil);
	}
	
	UIAlertView *alertView = [[[UIAlertView alloc] initWithTitle:errorTitle 
														 message:errorMessage
														delegate:nil 
											   cancelButtonTitle:NSLocalizedString(@"OK", nil) 
											   otherButtonTitles:nil] autorelease];
	[alertView show];
}


- (void)connectionStarted:(NSString *)connectionIdentifier {
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] showNetworkActivityIndicator];
}

- (void)connectionFinished:(NSString *)connectionIdentifier {
	[(MIT_MobileAppDelegate *)[[UIApplication sharedApplication] delegate] hideNetworkActivityIndicator];
}

#pragma mark -
#pragma mark Facebook

- (void)startupFacebook {
    if (!_facebook) {
		NSString *facebookAppID = [[_preferences objectForKey:KGOSocialMediaTypeFacebook] objectForKey:@"AppID"];
        _facebook = [[Facebook alloc] initWithAppId:facebookAppID];
    }
}

- (void)shutdownFacebook {
	if (_facebook) {
		[_facebook release];
		_facebook = nil;
	}
}

- (void)shareOnFacebook:(NSString *)attachment prompt:(NSString *)prompt {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:attachment forKey:@"attachment"];

	if (prompt) {
		[params setObject:prompt forKey:@"user_message_prompt"];
	}
    
    // if we want to add an arbitrary list of links, do something like the following:
    /*
     NSDictionary* actionLinks = [NSArray arrayWithObjects:
     [NSDictionary dictionaryWithObjectsAndKeys:@"Always Running",@"text",@"http://itsti.me/",@"href", nil],
     nil];
     [params setObject:actionLinks forKey:@"action_links"];
     */    
    
    [_facebook dialog:@"feed" andParams:params andDelegate:self];
}


- (void)loginFacebookWithDelegate:(id<FacebookWrapperDelegate>)delegate {
	self.facebookDelegate = delegate;
	
	if ([_facebook isSessionValid]) {
		[self.facebookDelegate facebookDidLogin];
		
	} else {	
		// from sample code in facebook-for-ios DemoApp
		NSArray *permissions = [NSArray arrayWithObjects:@"read_stream", @"offline_access",nil];
		[_facebook authorize:permissions delegate:self];
	}
}

- (void)logoutFacebook {
    if (_facebook) {
        [_facebook logout:self];
    }
}

#pragma mark Facebook - FBSessionDelegate

/**
 * Called when the user has logged in successfully.
 */
- (void)fbDidLogin {
	[self.facebookDelegate facebookDidLogin];
}

/**
 * Called when the user canceled the authorization dialog.
 */
-(void)fbDidNotLogin:(BOOL)cancelled {
    NSLog(@"failed to log in to facebook");
}

/**
 * Called when the request logout has succeeded.
 */
- (void)fbDidLogout {
	[self.facebookDelegate facebookDidLogout];
}

#pragma mark Facebook - FBRequestDelegate

/**
 * Called when the Facebook API request has returned a response. This callback
 * gives you access to the raw response. It's called before
 * (void)request:(FBRequest *)request didLoad:(id)result,
 * which is passed the parsed response object.
 */
- (void)request:(FBRequest *)request didReceiveResponse:(NSURLResponse *)response {
    NSLog(@"received response");
};

/**
 * Called when a request returns and its response has been parsed into an object.
 * The resulting object may be a dictionary, an array, a string, or a number, depending
 * on the format of the API response.
 * If you need access to the raw response, use
 * (void)request:(FBRequest *)request didReceiveResponse:(NSURLResponse *)response.
 */
- (void)request:(FBRequest *)request didLoad:(id)result {
    DLog(@"%@", [result description]);
    if ([result isKindOfClass:[NSArray class]]) {
        result = [result objectAtIndex:0];
    }
};

/**
 * Called when an error prevents the Facebook API request from completing successfully.
 */
- (void)request:(FBRequest *)request didFailWithError:(NSError *)error {
    DLog(@"%@", [error description]);
};

#pragma mark Facebook - FBDialogDelegate

/**
 * Called when a UIServer Dialog successfully return.
 */
- (void)dialogDidComplete:(FBDialog *)dialog {
    DLog(@"published successfully");
}

@end