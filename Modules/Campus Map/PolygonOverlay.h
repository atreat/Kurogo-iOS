#import <MapKit/MapKit.h>

@interface PolygonOverlayView : MKOverlayView
{
}

@end

// this class should never be instantiated before +[TileServerManager isInitialized] returns true
@interface PolygonOverlay : NSObject <MKOverlay>
{
    CLLocationCoordinate2D _coordinate;
    MKMapRect _boundingMapRect;
    
    NSArray *_rings;
}

- (id)initWithRings:(NSArray *)rings;

@property (nonatomic, retain) NSArray *rings;

@end
