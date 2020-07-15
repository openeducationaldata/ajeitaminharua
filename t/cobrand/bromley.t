use CGI::Simple;
use Test::MockModule;
use Test::MockTime qw(:all);
use Test::Output;
use FixMyStreet::TestMech;
use FixMyStreet::Script::Reports;
my $mech = FixMyStreet::TestMech->new;

# Mock fetching bank holidays
my $uk = Test::MockModule->new('FixMyStreet::Cobrand::UK');
$uk->mock('_fetch_url', sub { '{}' });

# Create test data
my $user = $mech->create_user_ok( 'bromley@example.com', name => 'Bromley' );
my $body = $mech->create_body_ok( 2482, 'Bromley Council',
    { can_be_devolved => 1, send_extended_statuses => 1, comment_user => $user });
my $contact = $mech->create_contact_ok(
    body_id => $body->id,
    category => 'Other',
    email => 'LIGHT',
);
$contact->set_extra_metadata(id_field => 'service_request_id_ext');
$contact->set_extra_fields(
    { code => 'easting', datatype => 'number', },
    { code => 'northing', datatype => 'number', },
    { code => 'service_request_id_ext', datatype => 'number', },
    { code => 'service_sub_code', values => [ { key => 'RED', name => 'Red' }, { key => 'BLUE', name => 'Blue' } ], },
);
$contact->update;
my $tfl = $mech->create_body_ok( 2482, 'TfL');
$mech->create_contact_ok(
    body_id => $tfl->id,
    category => 'Traffic Lights',
    email => 'tfl@example.org',
);

my $waste = $mech->create_contact_ok(
    body => $body,
    category => 'Report missed collection',
    email => 'missed',
    send_method => 'Open311',
    endpoint => 'waste-endpoint',
);
$waste->set_extra_metadata(group => ['Waste']);
$waste->update;

my @reports = $mech->create_problems_for_body( 1, $body->id, 'Test', {
    latitude => 51.402096,
    longitude => 0.015784,
    cobrand => 'bromley',
    user => $user,
});
my $report = $reports[0];

for my $update ('in progress', 'unable to fix') {
    FixMyStreet::DB->resultset('Comment')->find_or_create( {
        problem_state => $update,
        problem_id => $report->id,
        user_id    => $user->id,
        name       => 'User',
        mark_fixed => 'f',
        text       => "This update marks it as $update",
        state      => 'confirmed',
        confirmed  => 'now()',
        anonymous  => 'f',
    } );
}

# Test Bromley special casing of 'unable to fix'
$mech->get_ok( '/report/' . $report->id );
$mech->content_contains( 'marks it as in progress' );
$mech->content_contains( 'State changed to: In progress' );
$mech->content_contains( 'marks it as unable to fix' );
$mech->content_contains( 'State changed to: No further action' );

for my $test (
    {
        desc => 'testing special Open311 behaviour',
        updates => {},
        expected => {
          'attribute[easting]' => 540315,
          'attribute[northing]' => 168935,
          'attribute[service_request_id_ext]' => $report->id,
          'attribute[report_title]' => 'Test Test 1 for ' . $body->id,
          'jurisdiction_id' => 'FMS',
          address_id => undef,
        },
    },
    {
        desc => 'testing Open311 behaviour with no map click or postcode',
        updates => {
            used_map => 0,
            postcode => ''
        },
        expected => {
          'attribute[easting]' => 540315,
          'attribute[northing]' => 168935,
          'attribute[service_request_id_ext]' => $report->id,
          'jurisdiction_id' => 'FMS',
          'address_id' => '#NOTPINPOINTED#',
        },
    },
    {
        desc => 'asset ID',
        feature_id => '1234',
        expected => {
          'attribute[service_request_id_ext]' => $report->id,
          'attribute[report_title]' => 'Test Test 1 for ' . $body->id . ' | ID: 1234',
        },
    },
) {
    subtest $test->{desc}, sub {
        $report->$_($test->{updates}->{$_}) for keys %{$test->{updates}};
        $report->$_(undef) for qw/ whensent send_method_used external_id /;
        $report->set_extra_fields({ name => 'feature_id', value => $test->{feature_id} })
            if $test->{feature_id};
        $report->update;
        $body->update( { send_method => 'Open311', endpoint => 'http://bromley.endpoint.example.com', jurisdiction => 'FMS', api_key => 'test', send_comments => 1 } );
        my $test_data;
        FixMyStreet::override_config {
            STAGING_FLAGS => { send_reports => 1 },
            ALLOWED_COBRANDS => [ 'fixmystreet', 'bromley' ],
            MAPIT_URL => 'http://mapit.uk/',
        }, sub {
            $test_data = FixMyStreet::Script::Reports::send();
        };
        $report->discard_changes;
        ok $report->whensent, 'Report marked as sent';
        is $report->send_method_used, 'Open311', 'Report sent via Open311';
        is $report->external_id, 248, 'Report has right external ID';

        my $req = $test_data->{test_req_used};
        my $c = CGI::Simple->new($req->content);
        is $c->param($_), $test->{expected}->{$_}, "Request had correct $_"
            for keys %{$test->{expected}};
    };
}

for my $test (
    {
        cobrand => 'bromley',
        fields => {
            submit_update   => 1,
            username => 'unregistered@example.com',
            update          => 'Update from an unregistered user',
            add_alert       => undef,
            first_name            => 'Unreg',
            last_name            => 'User',
            fms_extra_title => 'DR',
            may_show_name   => undef,
        }
    },
    {
        cobrand => 'fixmystreet',
        fields => {
            submit_update   => 1,
            username => 'unregistered@example.com',
            update          => 'Update from an unregistered user',
            add_alert       => undef,
            name            => 'Unreg User',
            fms_extra_title => 'DR',
            may_show_name   => undef,
        }
    },
)
{
    subtest 'check Bromley update emails via ' . $test->{cobrand} . ' cobrand are correct' => sub {
        $mech->log_out_ok();
        $mech->clear_emails_ok();

        my $report_id = $report->id;

        FixMyStreet::override_config {
            ALLOWED_COBRANDS => [ $test->{cobrand} ],
        }, sub {
            $mech->get_ok("/report/$report_id");
            $mech->submit_form_ok(
                {
                    with_fields => $test->{fields}
                },
                'submit update'
            );
        };
        $mech->content_contains('Nearly done! Now check your email');

        my $body = $mech->get_text_body_from_email;
        like $body, qr/This update will be sent to Bromley Council/i, "Email indicates problem will be sent to Bromley";
        unlike $body, qr/Note that we do not send updates to/i, "Email does not say updates aren't sent to Bromley";

        my $unreg_user = FixMyStreet::DB->resultset('User')->find( { email => 'unregistered@example.com' } );

        ok $unreg_user, 'found user';

        $mech->delete_user( $unreg_user );
    };
}

subtest 'check display of TfL and waste reports' => sub {
    $mech->create_problems_for_body( 1, $tfl->id, 'TfL Test', {
        latitude => 51.402096,
        longitude => 0.015784,
        cobrand => 'bromley',
        user => $user,
    });
    $mech->get_ok( '/report/' . $report->id );
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        MAPIT_URL => 'http://mapit.uk/',
    }, sub {
        $mech->follow_link_ok({ text_regex => qr/Back to all reports/i });
    };
    $mech->content_like(qr{<a title="TfL Test[^>]*www.example.org[^>]*><img[^>]*grey});
    $mech->content_like(qr{<a title="Test Test[^>]*href="/[^>]*><img[^>]*yellow});
    $mech->content_lacks('Report missed collection');
};

subtest 'check geolocation overrides' => sub {
    my $cobrand = FixMyStreet::Cobrand::Bromley->new;
    foreach my $test (
        { query => 'Main Rd, BR1', town => 'Bromley', string => 'Main Rd' },
        { query => 'Main Rd, BR3', town => 'Beckenham', string => 'Main Rd' },
        { query => 'Main Rd, BR4', town => 'West Wickham', string => 'Main Rd' },
        { query => 'Main Rd, BR5', town => 'Orpington', string => 'Main Rd' },
        { query => 'Main Rd, BR7', town => 'Chislehurst', string => 'Main Rd' },
        { query => 'Main Rd, BR8', town => 'Swanley', string => 'Main Rd' },
        { query => 'Old Priory Avenue', town => 'BR6 0PL', string => 'Old Priory Avenue' },
    ) {
        my $res = $cobrand->disambiguate_location($test->{query});
        is $res->{town}, $test->{town}, "Town matches $test->{town}";
        is $res->{string}, $test->{string}, "String matches $test->{string}";
    }
};

subtest 'check special subcategories in admin' => sub {
    $mech->create_user_ok('superuser@example.com', is_superuser => 1);
    $mech->log_in_ok('superuser@example.com');
    $user->update({ from_body => $body->id });
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        MAPIT_URL => 'http://mapit.uk/',
    }, sub {
        $mech->get_ok('/admin/users/' . $user->id);
        $mech->submit_form_ok({ with_fields => { 'contacts['.$contact->id.']' => 1, 'contacts[BLUE]' => 1 } });
    };
    $user->discard_changes;
    is_deeply $user->get_extra_metadata('categories'), [ $contact->id ];
    is_deeply $user->get_extra_metadata('subcategories'), [ 'BLUE' ];
};

subtest 'check heatmap page' => sub {
    $user->update({ area_ids => [ 60705 ] });
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        MAPIT_URL => 'http://mapit.uk/',
        COBRAND_FEATURES => { category_groups => { bromley => 1 }, heatmap => { bromley => 1 } },
    }, sub {
        $mech->log_in_ok($user->email);
        $mech->get_ok('/dashboard/heatmap?end_date=2018-12-31');
        $mech->get_ok('/dashboard/heatmap?filter_category=RED&ajax=1');
    };
};

subtest 'test open enquiries' => sub {
    set_fixed_time('2020-05-19T12:00:00Z'); # After sample food waste collection
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        COBRAND_FEATURES => {
            echo => { bromley => { sample_data => 1 } },
            waste => { bromley => 1 }
        },
    }, sub {
        $mech->get_ok('/waste/uprn/12345');
        $mech->follow_link_ok({ text => 'Report a problem with a food waste collection' });
        $mech->content_contains('Waste spillage');
        $mech->content_lacks('Gate not closed');
    };
    restore_time();
};

subtest 'test reporting before/after completion' => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        COBRAND_FEATURES => {
            echo => { bromley => { sample_data => 1 } },
            waste => { bromley => 1 }
        },
    }, sub {
        set_fixed_time('2020-05-27T11:00:00Z');
        $mech->get_ok('/waste/uprn/12345');
        $mech->content_contains('completed at 10:00am');
        $mech->content_lacks('Report a refuse collection');
        $mech->content_contains('Report a paper &amp; cardboard collection as missed');
        set_fixed_time('2020-05-28T12:00:00Z');
        $mech->get_ok('/waste/uprn/12345');
        $mech->content_contains('Report a paper &amp; cardboard collection as missed');
        set_fixed_time('2020-05-29T12:00:00Z');
        $mech->get_ok('/waste/uprn/12345');
        $mech->content_contains('Report a paper &amp; cardboard collection as missed');
        set_fixed_time('2020-05-30T12:00:00Z');
        $mech->get_ok('/waste/uprn/12345');
        $mech->content_lacks('Report a paper &amp; cardboard collection as missed');
    };
    restore_time();
};

subtest 'test waste max-per-day' => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        COBRAND_FEATURES => {
            echo => { bromley => { max_per_day => 1, sample_data => 1 } },
            waste => { bromley => 1 }
        },
    }, sub {
        SKIP: {
            skip( "No memcached", 2 ) unless Memcached::increment('bromley-test');
            Memcached::delete("bromley-test");
            $mech->get_ok('/waste/uprn/12345');
            $mech->get('/waste/uprn/12345');
            is $mech->res->code, 403, 'Now forbidden';
        }
    };

};

package SOAP::Result;
sub result { return $_[0]->{result}; }
sub new { my $c = shift; bless { @_ }, $c; }

package main;

subtest 'updating of waste reports' => sub {
    my $integ = Test::MockModule->new('SOAP::Lite');
    $integ->mock(call => sub {
        my ($cls, @args) = @_;
        my $method = $args[0]->name;
        if ($method eq 'GetEvent') {
            my ($key, $type, $value) = ${$args[3]->value}->value;
            my $external_id = ${$value->value}->value->value;
            my ($waste, $event_state_id, $resolution_code) = split /-/, $external_id;
            return SOAP::Result->new(result => {
                EventStateId => $event_state_id,
                EventTypeId => '2104',
                LastUpdatedDate => { OffsetMinutes => 60, DateTime => '2020-06-24T14:00:00Z' },
                ResolutionCodeId => $resolution_code,
            });
        } elsif ($method eq 'GetEventType') {
            return SOAP::Result->new(result => {
                Workflow => { States => { State => [
                    { CoreState => 'New', Name => 'New', Id => 15001 },
                    { CoreState => 'Pending', Name => 'Unallocated', Id => 15002 },
                    { CoreState => 'Pending', Name => 'Allocated to Crew', Id => 15003 },
                    { CoreState => 'Closed', Name => 'Completed', Id => 15004,
                      ResolutionCodes => { StateResolutionCode => [
                        { ResolutionCodeId => 201, Name => '' },
                        { ResolutionCodeId => 202, Name => 'Spillage on Arrival' },
                      ] } },
                    { CoreState => 'Closed', Name => 'Not Completed', Id => 15005,
                      ResolutionCodes => { StateResolutionCode => [
                        { ResolutionCodeId => 203, Name => 'Nothing Found' },
                        { ResolutionCodeId => 204, Name => 'Too Heavy' },
                        { ResolutionCodeId => 205, Name => 'Inclement Weather' },
                      ] } },
                    { CoreState => 'Closed', Name => 'Rejected', Id => 15006,
                      ResolutionCodes => { StateResolutionCode => [
                        { ResolutionCodeId => 206, Name => 'Out of Time' },
                        { ResolutionCodeId => 207, Name => 'Duplicate' },
                      ] } },
                ] } },
            });
        } else {
            is $method, 'UNKNOWN';
        }
    });

    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        COBRAND_FEATURES => {
            echo => { bromley => { url => 'https://www.example.org/' } },
            waste => { bromley => 1 }
        },
    }, sub {
        ($report) = $mech->create_problems_for_body(1, $body->id, 'Report missed collection', {
            category => 'Report missed collection',
            cobrand_data => 'waste',
        });
        my $cobrand = FixMyStreet::Cobrand::Bromley->new;

        $report->update({ external_id => 'waste-15001-' });
        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/Fetching data for report/;
        $report->discard_changes;
        is $report->comments->count, 0, 'No new update';
        is $report->state, 'confirmed', 'No state change';

        $report->update({ external_id => 'waste-15003-' });
        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/Updating report to state action scheduled, Allocated to Crew/;
        $report->discard_changes;
        is $report->comments->count, 1, 'A new update';
        is $report->state, 'action scheduled', 'A state change';

        $report->update({ external_id => 'waste-15003-' });
        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/Latest update matches fetched state/;
        $report->discard_changes;
        is $report->comments->count, 1, 'No new update';
        is $report->state, 'action scheduled', 'State unchanged';

        $report->update({ external_id => 'waste-15004-201' });
        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/Updating report to state fixed - council, Completed/;
        $report->discard_changes;
        is $report->comments->count, 2, 'A new update';
        is $report->state, 'fixed - council', 'Changed to fixed';

        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/^$/, 'No open reports';

        $report->update({ external_id => 'waste-15005-205', state => 'confirmed' });
        stdout_like {
            $cobrand->waste_fetch_events(1);
        } qr/Updating report to state unable to fix, Inclement Weather/;
        $report->discard_changes;
        is $report->comments->count, 3, 'A new update';
        is $report->state, 'unable to fix', 'A state change';
    };

    FixMyStreet::override_config {
        ALLOWED_COBRANDS => 'bromley',
        COBRAND_FEATURES => {
            echo => { bromley => {
                url => 'https://www.example.org/',
                receive_action => 'action',
                receive_username => 'un',
                receive_password => 'password',
            } },
            waste => { bromley => 1 }
        },
    }, sub {
        FixMyStreet::App->log->disable('info');

        $mech->get('/waste/echo');
        is $mech->res->code, 405, 'Cannot GET';

        $mech->post('/waste/echo', Content_Type => 'text/xml');
        is $mech->res->code, 400, 'No body';

        $mech->post('/waste/echo', Content_Type => 'text/xml', SOAPAction => 'bad-action', Content => 'content');
        is $mech->res->code, 400, 'Bad action';

        my $in = '<Envelope><Header><Security><UsernameToken><Username></Username><Password></Password></UsernameToken></Security></Header><Body></Body></Envelope>';
        $mech->post('/waste/echo', Content_Type => 'text/xml', SOAPAction => 'action', Content => $in);
        is $mech->res->code, 400, 'Bad auth';

        $in = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<Envelope>
  <Header><Security><UsernameToken><Username>un</Username><Password>password</Password></UsernameToken></Security></Header>
  <Body>
    <NotifyEventUpdated>
      <event>
        <Guid>waste-15005-205</Guid>
        <EventTypeId>2104</EventTypeId>
        <EventStateId>15006</EventStateId>
        <ResolutionCodeId>207</ResolutionCodeId>
      </event>
    </NotifyEventUpdated>
  </Body>
</Envelope>
EOF
        $mech->post('/waste/echo', Content_Type => 'text/xml', SOAPAction => 'action', Content => $in);
        #$report->update({ external_id => 'waste-15005-205', state => 'confirmed' });
        is $report->comments->count, 4, 'A new update';
        $report->discard_changes;
        is $report->state, 'closed', 'A state change';

        FixMyStreet::App->log->enable('info');
    };
};

done_testing();
