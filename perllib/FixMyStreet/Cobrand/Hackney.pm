package FixMyStreet::Cobrand::Hackney;
use parent 'FixMyStreet::Cobrand::Whitelabel';

use strict;
use warnings;
use mySociety::EmailUtil qw(is_valid_email is_valid_email_list);

sub council_area_id { return 2508; }
sub council_area { return 'Hackney'; }
sub council_name { return 'Hackney Council'; }
sub council_url { return 'hackney'; }
sub send_questionnaires { 0 }

sub disambiguate_location {
    my $self    = shift;
    my $string  = shift;

    my $town = 'Hackney';

    # Teale Street is on the boundary with Tower Hamlets and
    # shows the 'please use fixmystreet.com' message, but Hackney
    # do provide services on that road.
    ($string, $town) = ('E2 9AA', '') if $string =~ /^teale\s+st/i;

    return {
        %{ $self->SUPER::disambiguate_location() },
        string => $string,
        town   => $town,
        centre => '51.552267,-0.063316',
        bounds => [ 51.519814, -0.104511, 51.577784, -0.016527 ],
    };
}

sub do_not_reply_email { shift->feature('do_not_reply_email') }

sub verp_email_domain { shift->feature('verp_email_domain') }

sub get_geocoder {
    return 'OSM'; # default of Bing gives poor results, let's try overriding.
}

sub geocoder_munge_query_params {
    my ($self, $params) = @_;

    $params->{addressdetails} = 1;
}

sub geocoder_munge_results {
    my ($self, $result) = @_;
    if (my $a = $result->{address}) {
        if ($a->{road} && $a->{suburb} && $a->{postcode}) {
            $result->{display_name} = "$a->{road}, $a->{suburb}, $a->{postcode}";
            return;
        }
    }
    $result->{display_name} = '' unless $result->{display_name} =~ /Hackney/;
    $result->{display_name} =~ s/, United Kingdom$//;
    $result->{display_name} =~ s/, London, Greater London, England//;
    $result->{display_name} =~ s/, London Borough of Hackney//;
}


sub open311_config {
    my ($self, $row, $h, $params) = @_;

    $params->{multi_photos} = 1;
}

sub open311_extra_data {
    my ($self, $row, $h, $extra, $contact) = @_;

    my $open311_only = [
        { name => 'report_url',
          value => $h->{url} },
        { name => 'title',
          value => $row->title },
        { name => 'description',
          value => $row->detail },
        { name => 'category',
          value => $row->category },
    ];

    # Make sure contact 'email' set correctly for Open311
    if (my $sent_to = $row->get_extra_metadata('sent_to')) {
        $row->unset_extra_metadata('sent_to');
        my $code = $sent_to->{$contact->email};
        $contact->email($code) if $code;
    }

    return $open311_only;
}

sub map_type { 'OSM' }

sub default_map_zoom { 6 }

sub admin_user_domain { 'hackney.gov.uk' }

sub social_auth_enabled {
    my $self = shift;

    return $self->feature('oidc_login') ? 1 : 0;
}

sub anonymous_account {
    my $self = shift;
    return {
        email => $self->feature('anonymous_account') . '@' . $self->admin_user_domain,
        name => 'Anonymous user',
    };
}

sub open311_skip_existing_contact {
    my ($self, $contact) = @_;

    # For Hackney we want the 'protected' flag to prevent any changes to this
    # contact at all.
    return $contact->get_extra_metadata("open311_protect") ? 1 : 0;
}

sub open311_filter_contacts_for_deletion {
    my ($self, $contacts) = @_;

    # Don't delete open311 protected contacts when importing
    return $contacts->search({
        extra => { -not_like => '%T15:open311_protect,I1:1%' },
    });
}

sub problem_is_within_area_type {
    my ($self, $problem, $type) = @_;
    my $layer_map = {
        park => "greenspaces:hackney_park",
        estate => "housing:lbh_estate",
    };
    my $layer = $layer_map->{$type};
    return unless $layer;

    my ($x, $y) = $problem->local_coords;

    my $cfg = {
        url => "https://map.hackney.gov.uk/geoserver/wfs",
        srsname => "urn:ogc:def:crs:EPSG::27700",
        typename => $layer,
        outputformat => "json",
        filter => "<Filter xmlns:gml=\"http://www.opengis.net/gml\"><Intersects><PropertyName>geom</PropertyName><gml:Point srsName=\"27700\"><gml:coordinates>$x,$y</gml:coordinates></gml:Point></Intersects></Filter>",
    };

    my $features = $self->_fetch_features($cfg, $x, $y) || [];
    return scalar @$features ? 1 : 0;
}

sub get_body_sender {
    my ( $self, $body, $problem ) = @_;

    my $contact = $body->contacts->search( { category => $problem->category } )->first;

    if (my ($park, $estate, $other) = $self->_split_emails($contact->email)) {
        my $to = $other;
        if ($self->problem_is_within_area_type($problem, 'park')) {
            $to = $park;
        } elsif ($self->problem_is_within_area_type($problem, 'estate')) {
            $to = $estate;
        }
        $problem->set_extra_metadata(sent_to => { $contact->email => $to });
        if (is_valid_email($to)) {
            return { method => 'Email', contact => $contact };
        }
    }
    return $self->SUPER::get_body_sender($body, $problem);
}

# Translate email address to actual delivery address
sub munge_sendreport_params {
    my ($self, $row, $h, $params) = @_;

    my $sent_to = $row->get_extra_metadata('sent_to') or return;
    $row->unset_extra_metadata('sent_to');
    for my $recip (@{$params->{To}}) {
        my ($email, $name) = @$recip;
        $recip->[0] = $sent_to->{$email} if $sent_to->{$email};
    }
}

sub _split_emails {
    my ($self, $email) = @_;

    my $parts = join '\s*', qw(^ park : (.*?) ; estate : (.*?) ; other : (.*?) $);
    my $regex = qr/$parts/i;

    if (my ($park, $estate, $other) = $email =~ $regex) {
        return ($park, $estate, $other);
    }
    return ();
}

sub validate_contact_email {
    my ( $self, $email ) = @_;

    return 1 if is_valid_email_list($email);

    my @emails = grep { $_ } $self->_split_emails($email);
    return unless @emails;
    return 1 if is_valid_email_list(join(",", @emails));
}

1;
