/*
 * fixmystreet.js
 * FixMyStreet JavaScript
 */

function form_category_onchange() {
    var cat = $('#form_category');
    var args = {
        category: cat.val()
    };

    if ( typeof fixmystreet !== 'undefined' ) {
        args.latitude = fixmystreet.latitude;
        args.longitude = fixmystreet.longitude;
    } else {
        args.latitude = $('input[name="latitude"]').val();
        args.longitude = $('input[name="longitude"]').val();
    }

    $.getJSON('/report/new/category_extras', args, function(data) {
        if ( data.category_extra ) {
            if ( $('#category_meta').size() ) {
                $('#category_meta').html( data.category_extra);
            } else {
                $('#form_category_row').after( data.category_extra );
            }
        } else {
            $('#category_meta').empty();
        }
    });
}

/*
 * general height fixing function
 *
 * elem1: element to check against
 * elem2: target element
 * offest: this will be added (if present) to the final value, useful for height errors
 */
function heightFix(elem1, elem2, offset){
    var h1 = $(elem1).height(),
        h2 = $(elem2).height();
    if(offset === undefined){
        offset = 0;
    }
    if(h1 > h2){
        $(elem2).css({'min-height':h1+offset});
    }
}


/*
 * very simple tab function
 *
 * elem: trigger element, must have an href attribute (so probably needs to be an <a>)
 */
function tabs(elem)
{
    var href = elem.attr('href');
    //stupid IE sometimes adds the full uri into the href attr, so trim
    var start = href.indexOf('#'),
        target = href.slice(start, href.length);

    if(!$(target).hasClass('open'))
    {
        //toggle class on nav
        $('.tab-nav .active').removeClass('active');
        elem.addClass('active');
 
        //hide / show the right tab
        $('.tab.open').hide().removeClass('open');
        $(target).show().addClass('open');
    }
}


$(function(){
    //add mobile class if small screen
    if(Modernizr.mq('only screen and (max-width:48em)')) {
        $('html').addClass('mobile');
    } else {

        // Make map full screen on non-mobile sizes.
        $('#map_box').prependTo('.wrapper').css({
            zIndex: 0, position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            width: '100%', height: '100%',
            margin: 0
        }).data('size', 'full');

    }
    //heightfix the desktop .content div
    if(Modernizr.mq('only screen and (min-width:48em)')) {
        if (!($('body').hasClass('frontpage'))){
            heightFix(window, '.content', -176);
        }
    }

    if ($.browser.opera) {
        $('html').addClass('opera');
    }

    $('html').removeClass('no-js').addClass('js');

    $('#pc').focus();

    $('input[type=submit]').removeAttr('disabled');
    /*
    $('#mapForm').submit(function() {
        if (this.submit_problem) {
            $('input[type=submit]', this).prop("disabled", true);
        }
        return true;
    });
    */

    if (!$('#been_fixed_no').prop('checked') && !$('#been_fixed_unknown').prop('checked')) {
        $('#another_qn').hide();
    }
    $('#been_fixed_no').click(function() {
        $('#another_qn').show('fast');
    });
    $('#been_fixed_unknown').click(function() {
        $('#another_qn').show('fast');
    });
    $('#been_fixed_yes').click(function() {
        $('#another_qn').hide('fast');
    });

    var timer;
    function email_alert_close() {
        $('#email_alert_box').hide('fast');
    }

    // FIXME - needs to use translated string
    jQuery.validator.addMethod('validCategory', function(value, element) {
        return this.optional(element) || value != '-- Pick a category --'; }, validation_strings.category );

    jQuery.validator.addMethod('validName', function(value, element) {
        var validNamePat = /\ba\s*n+on+((y|o)mo?u?s)?(ly)?\b/i;
        return this.optional(element) || value.length > 5 && value.match( /\S/ ) && !value.match( validNamePat ); }, validation_strings.category );

    var form_submitted = 0;
    var submitted = false;

    $("form.validate").validate({
        rules: {
            title: { required: true },
            detail: { required: true },
            email: { required: true },
            update: { required: true },
            rznvy: { required: true }
        },
        messages: validation_strings,
        onkeyup: false,
        onfocusout: false,
        errorElement: 'div',
        errorClass: 'form-error',
        // we do this to stop things jumping around on blur
        success: function (err) { if ( form_submitted ) { err.addClass('label-valid').removeClass('label-valid-hidden').html( '&nbsp;' ); } else { err.addClass('label-valid-hidden'); } },
        errorPlacement: function( error, element ) {
            element.before( error );
        },
        submitHandler: function(form) {
            if (form.submit_problem) {
                $('input[type=submit]', form).prop("disabled", true);
            }

            form.submit();
        },
        // make sure we can see the error message when we focus on invalid elements
        showErrors: function( errorMap, errorList ) {
            if ( submitted && errorList.length ) {
               $(window).scrollTop( $(errorList[0].element).offset().top - 120 );
            }
            this.defaultShowErrors();
            submitted = false;
        },
        invalidHandler: function(form, validator) { submitted = true; }
    });

    $('input[type=submit]').click( function(e) { form_submitted = 1; } );

    /* set correct required status depending on what we submit 
    * NB: need to add things to form_category as the JS updating 
    * of this we do after a map click removes them */
    $('#submit_sign_in').click( function(e) {
        $('#form_category').addClass('required validCategory').removeClass('valid');
        $('#form_name').removeClass();
    } );

    $('#submit_register').click( function(e) { 
        $('#form_category').addClass('required validCategory').removeClass('valid');
        $('#form_name').addClass('required validName');
    } );

    $('#problem_submit > input[type="submit"]').click( function(e) { 
        $('#form_category').addClass('required validCategory').removeClass('valid');
        $('#form_name').addClass('required validName');
    } );

    $('#update_post').click( function(e) { 
        $('#form_name').addClass('required').removeClass('valid');
    } );

    $('#form_category').change( form_category_onchange );

    // Geolocation
    if (geo_position_js.init()) {
        $('#postcodeForm').after('<a href="#" id="geolocate_link">&hellip; or locate me automatically</a>');
        $('#geolocate_link').click(function(e) {
            e.preventDefault();
            // Spinny thing!
            $(this).append(' <img src="/i/flower.gif" alt="" align="bottom">');
            geo_position_js.getCurrentPosition(function(pos) {
                $('img', this).remove();
                var latitude = pos.coords.latitude;
                var longitude = pos.coords.longitude;
                location.href = '/around?latitude=' + latitude + ';longitude=' + longitude;
            }, function(err) {
                $('img', this).remove();
                if (err.code == 1) { // User said no
                } else if (err.code == 2) { // No position
                    $(this).html("Could not look up location");
                } else if (err.code == 3) { // Too long
                    $('this').html("No result returned");
                } else { // Unknown
                    $('this').html("Unknown error");
                }
            }, {
                timeout: 10000
            });
        });
    }

    /* 
     * Report a problem page 
     */
    //desktop
    if($('#report-a-problem-sidebar:visible').length > 0){
        heightFix('#report-a-problem-sidebar:visible', '.content', 26);
    }

    //show/hide notes on mobile
    $('.mobile #report-a-problem-sidebar').after('<a href="#" class="rap-notes-trigger button-right">How to send successful reports</a>').hide();
    $('.mobile').on('click', '.rap-notes-trigger', function(e){
        e.preventDefault();
        //check if we've already moved the notes
        if($('.rap-notes').length > 0){
            //if we have, show and hide .content
            $('.mobile .content').hide();
            $('.rap-notes').show();
        }else{
            //if not, move them and show, hiding .content
            $('.mobile .content').after('<div class="content rap-notes"></div>').hide();
            $('#report-a-problem-sidebar').appendTo('.rap-notes').show().after('<a href="#" class="rap-notes-close button-left">BACK</a>');
        }
    });
    $('.mobile').on('click', '.rap-notes-close', function(e){
        e.preventDefault();
        //hide notes, show .content
        $('.mobile .content').show();
        $('.rap-notes').hide();
        $('html, body').animate({scrollTop:0}, 1000);
    });

    //move 'skip this step' link on mobile
    $('.mobile #skip-this-step').hide();
    $('.mobile #skip-this-step a').appendTo('#key-tools').addClass('chevron').wrap('<li>');

    /*
     * Tabs
     */
    //make initial tab active
    $('.tab-nav a:first').addClass('active');
    $('.tab:first').addClass('open');
    
    //hide other tabs
    $('.tab').not('.open').hide();
    
    //set up click event
    $(".tab-nav").on('click', 'a', function(e){
        e.preventDefault();
        tabs($(this));
    });

    /*
     * Skip to nav on mobile
     */
    $('.mobile').on('click', '#nav-link', function(e){
        e.preventDefault();
        var foo = $('.wrapper').height() - 500;
        $('html, body').animate({scrollTop:foo}, 1000);
    });


    /*
     * Show stuff on input focus
     */
    $('.form-focus-hidden').hide();
    $('.form-focus-trigger').on('focus', function(){
        $('.form-focus-hidden').fadeIn(500);
    });
});
