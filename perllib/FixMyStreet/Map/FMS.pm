# FixMyStreet:Map::FMS
# Bing and OS StreetView maps on FixMyStreet, using OpenLayers.
#
# Copyright (c) 2011 UK Citizens Online Democracy. All rights reserved.
# Email: matthew@mysociety.org; WWW: http://www.mysociety.org/

package FixMyStreet::Map::FMS;
use base 'FixMyStreet::Map::Bing';

use strict;

use constant ZOOM_LEVELS => 6;

sub map_template { 'fms' }

sub map_javascript { [
    '/vendor/OpenLayers/OpenLayers.wfs.js',
    '/js/map-OpenLayers.js',
    '/js/map-bing-ol.js',
    '/js/map-fms.js',
] }

sub map_tile_base { "oml" }

sub map_tiles {
    my ( $self, %params ) = @_;
    my ( $x, $y, $z ) = ( $params{x_tile}, $params{y_tile}, $params{zoom_act} );
    my $ni = in_northern_ireland_box( $params{latitude}, $params{longitude} );
    if ($params{aerial} || $ni || $z <= 11) {
        return $self->SUPER::map_tiles(%params);
    } elsif ($z >= 16) {
        my $tile_base = '//%stilma.mysociety.org/' . $self->map_tile_base . '/%d/%d/%d.png';
        return [
            sprintf($tile_base, 'a-', $z, $x-1, $y-1),
            sprintf($tile_base, 'b-', $z, $x, $y-1),
            sprintf($tile_base, 'c-', $z, $x-1, $y),
            sprintf($tile_base, '', $z, $x, $y),
        ];
    } elsif ($z > 11) {
        my $key = FixMyStreet->config('BING_MAPS_API_KEY');
        my $base = "//ecn.%s.tiles.virtualearth.net/tiles/r%s?g=8702&lbl=l1&productSet=mmOS&key=$key";
        return [
            sprintf($base, "t0", $self->get_quadkey($x-1, $y-1, $z)),
            sprintf($base, "t1", $self->get_quadkey($x,   $y-1, $z)),
            sprintf($base, "t2", $self->get_quadkey($x-1, $y,   $z)),
            sprintf($base, "t3", $self->get_quadkey($x,   $y,   $z)),
        ];
    }
}

sub in_northern_ireland_box {
    my ($lat, $lon) = @_;
    return 1 if $lat >= 54.015 && $lat <= 55.315 && $lon >= -8.18 && $lon <= -5.415;
    return 0;
}

1;
