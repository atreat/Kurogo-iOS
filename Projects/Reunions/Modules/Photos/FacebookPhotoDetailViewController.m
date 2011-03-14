#import "FacebookPhotoDetailViewController.h"
#import "UIKit+KGOAdditions.h"
#import "Foundation+KGOAdditions.h"
#import "KGOSocialMediaController+FacebookAPI.h"
#import "KGOAppDelegate.h"

@interface FacebookPhotoDetailViewController (Private)

- (void)getCommentsForPhoto;

@end



@implementation FacebookPhotoDetailViewController

@synthesize photo, photos;
/*
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
*/
- (void)dealloc
{
    [_comments release];
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark -

- (IBAction)commentButtonPressed:(UIBarButtonItem *)sender {
    FacebookCommentViewController *vc = [[[FacebookCommentViewController alloc] initWithNibName:@"FacebookCommentViewController" bundle:nil] autorelease];
    vc.delegate = self;
    vc.post = self.photo;
    [(KGOAppDelegate *)[[UIApplication sharedApplication] delegate] presentAppModalViewController:vc animated:YES];
}

- (IBAction)likeButtonPressed:(UIBarButtonItem *)sender {
    _likeButton.enabled = NO;
    if ([_likeButton.title isEqualToString:@"Like"]) {
        [[KGOSocialMediaController sharedController] likeFacebookPost:self.photo receiver:self callback:@selector(didLikePhoto:)];
    } else if ([_likeButton.title isEqualToString:@"Unlike"]) {
        [[KGOSocialMediaController sharedController] unlikeFacebookPost:self.photo receiver:self callback:@selector(didUnikePhoto:)];
    }
}

- (void)didLikePhoto:(id)result {
    DLog(@"%@", [result description]);
    if ([result isKindOfClass:[NSDictionary class]] && [[result stringForKey:@"result" nilIfEmpty:YES] isEqualToString:@"true"]) {
        _likeButton.enabled = YES;
        _likeButton.title = @"Unlike";
    }
}

- (void)didUnikePhoto:(id)result {
    NSLog(@"%@", [result description]);
    if ([result isKindOfClass:[NSDictionary class]] && [[result stringForKey:@"result" nilIfEmpty:YES] isEqualToString:@"true"]) {
        _likeButton.enabled = YES;
        _likeButton.title = @"Like";
    }
}

- (IBAction)bookmarkButtonPressed:(UIBarButtonItem *)sender {

}

- (void)displayPhoto {
    _thumbnail.imageURL = self.photo.src;
    _thumbnail.imageData = self.photo.data;
    [_thumbnail loadImage];
    
    if (!self.photo.comments.count) {
        [self getCommentsForPhoto];
    }
}

- (void)getCommentsForPhoto {
    NSString *objectID = self.photo.commentPath.length ? self.photo.commentPath : self.photo.identifier;
    NSString *path = [NSString stringWithFormat:@"%@/comments", objectID];
    [[KGOSocialMediaController sharedController] requestFacebookGraphPath:path
                                                                 receiver:self
                                                                 callback:@selector(didReceiveComments:)];
}

- (void)didReceiveComments:(id)result {
    NSLog(@"%@", [result description]);
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *resultDict = (NSDictionary *)result;
        NSArray *comments = [resultDict arrayForKey:@"data"];
        for (NSDictionary *commentData in comments) {
            FacebookComment *aComment = [FacebookComment commentWithDictionary:commentData];
            aComment.parent = self.photo;
        }
        
        NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
        [_comments release];
        _comments = [[self.photo.comments sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]] retain];
        
        [_tableView reloadData];
    }
}

- (void)didPostComment:(FacebookComment *)aComment {
    aComment.parent = self.photo;
    [_tableView reloadData];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
    [_comments release];
    _comments = [[self.photo.comments sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]] retain];
    
    _tableView.rowHeight = 100;
    CGRect frame = self.view.bounds;
    frame.size.height = floor(frame.size.width * 9 / 16); // need to tweak this aspect ratio
    _thumbnail = [[MITThumbnailView alloc] initWithFrame:frame];
    _thumbnail.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    _thumbnail.contentMode = UIViewContentModeScaleAspectFit;
    _tableView.tableHeaderView = _thumbnail;
    
    if (self.photos) {
        KGODetailPager *pager = [[[KGODetailPager alloc] initWithPagerController:self delegate:self] autorelease];
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:pager] autorelease];
    }
    
    [self displayPhoto];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - KGODetailPager

- (void)pager:(KGODetailPager *)pager showContentForPage:(id<KGOSearchResult>)content {
    [[KGOSocialMediaController sharedController] disconnectFacebookRequests:self]; // stop getting data for previous photo
    
    self.photo = (FacebookPhoto *)content;
    [self displayPhoto];
    
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
    [_comments release];
    _comments = [[self.photo.comments sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]] retain];
    
    [_tableView reloadData];
}

- (NSInteger)numberOfSections:(KGODetailPager *)pager {
    return 1;
}

- (NSInteger)pager:(KGODetailPager *)pager numberOfPagesInSection:(NSInteger)section {
    return self.photos.count;
}

- (id<KGOSearchResult>)pager:(KGODetailPager *)pager contentForPageAtIndexPath:(NSIndexPath *)indexPath {
    return [self.photos objectAtIndex:indexPath.row];
}

#pragma mark - Table view methods

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.photo.title;
    //return [NSString stringWithFormat:@"x users like this"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _comments.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    FacebookComment *aComment = [_comments objectAtIndex:indexPath.row];
    NSLog(@"%@", [aComment description]);
    
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }
    
    NSInteger commentTag = 80;
    NSInteger authorTag = 81;
    NSInteger dateTag = 82;
    
    UILabel *commentLabel = (UILabel *)[cell.contentView viewWithTag:commentTag];
    if (!commentLabel) {
        UIFont *commentFont = [UIFont systemFontOfSize:15];
        commentLabel = [UILabel multilineLabelWithText:aComment.text font:commentFont width:tableView.frame.size.width - 20];
        commentLabel.tag = commentTag;
        CGRect frame = commentLabel.frame;
        frame.origin.x = 10;
        frame.origin.y = 5;
        commentLabel.frame = frame;
    } else {
        commentLabel.text = aComment.text;
    }
    [cell.contentView addSubview:commentLabel];
    
    UILabel *authorLabel = (UILabel *)[cell.contentView viewWithTag:authorTag];
    if (!authorLabel) {
        UIFont *authorFont = [UIFont systemFontOfSize:13];
        authorLabel = [UILabel multilineLabelWithText:aComment.owner.name font:authorFont width:tableView.frame.size.width - 20];
        authorLabel.tag = authorTag;
        CGRect frame = authorLabel.frame;
        frame.origin.x = 10;
        frame.origin.y = 80;
        authorLabel.frame = frame;
    } else {
        authorLabel.text = aComment.owner.name;
    }
    [cell.contentView addSubview:authorLabel];
    
    UILabel *dateLabel = (UILabel *)[cell.contentView viewWithTag:dateTag];
    // TODO: use nsdateformatter, not this
    NSString *dateString = [NSString stringWithFormat:@"%@", aComment.date];
    if (!dateLabel) {
        UIFont *dateFont = [UIFont systemFontOfSize:13];
        dateLabel = [UILabel multilineLabelWithText:dateString font:dateFont width:tableView.frame.size.width - 20];
        dateLabel.tag = dateTag;
        CGRect frame = dateLabel.frame;
        frame.origin.x = 160;
        frame.origin.y = 80;
        dateLabel.frame = frame;
    } else {
        dateLabel.text = dateString;
    }
    [cell.contentView addSubview:dateLabel];
    
    return cell;
}

@end
