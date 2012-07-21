$(function() {
    var container = $('#container');
    var loading = $('<div>').addClass('loading').html($('<img>').attr('src', '/images/blocks.gif'));

    var genreMap = {};
    // keep handles to the genres by name
    $.each($('ul.genres li'), function(i, genre) {
        genreMap[$(genre).data('genre')] = $(genre);
    });

    var hash = window.location.hash;
    if(hash.indexOf('#') == 0) {
        hash = hash.slice(1); // remove the leading hash if there is one
    }

    var selectedGenres = [];
    var page = 0;
    if(hash.indexOf('/') >= 0) {
        // check if the genre has a slash, and thus a page number
        var tokens = hash.split('/');
        selectedGenres = tokens[0].split(',');
        page = tokens[1];
    } else {
        selectedGenres = hash.split(',');
    }

    if(selectedGenres.length < 1 || (selectedGenres.length == 1 && selectedGenres[0] == '')) {
        // default to all genres on
        selectedGenres = $.map(genreMap, function(v, k) { return k; });
    }

    // handle users selecting a genre
    $('ul.genres li').click(function() {
        var genre = $(this).data('genre');
        if($(this).hasClass('selected')) {
            selectedGenres.splice(selectedGenres.indexOf(genre), 1);
        } else {
            selectedGenres.push(genre);
        }
        page = 0;
        loadGenres(selectedGenres, page);
    });

    var loadGenres = function(genres, pageNum) {
        if(pageNum > 20) { return; }
        console.log("LOADING:", genres, pageNum);
        var urlPath = genres.join(',') + '/' + pageNum;
        window.location.hash = urlPath;

        _gaq.push(['_trackPageview', urlPath]);

        if(pageNum == 0) {
            // when its a new genre we should clear out the entries
            container.empty();
        }

        // select the appropriate nav elements
        $('ul.genres li').removeClass('selected');
        $.each(genres, function(i, genre) {
            genreMap[genre].addClass('selected');
        });

        // display the loading gif
        container.append(loading);

        $.getJSON('/mixes/' + urlPath, function(data) {
            var mixes = $('<ul>').addClass('mixes').addClass(pageNum);
            $.each(data, function(i, entry) {
                var mix = $('<li>').addClass('mix').addClass(entry.id);
                var iframe = $('<iframe>').attr('width', '100%')
                                          .attr('height', 166)
                                          .attr('scrolling', 'no')
                                          .attr('frameborder', 'no');
                var url = 'http://w.soundcloud.com/player/?url=' + entry.uri + '&show_artwork=true&show_comments=false';
                iframe.attr('src', url);
                iframe.addClass('mixframe');
                mix.html(iframe);
                mixes.append(mix);
            });
            container.append(mixes);
            $('div.loading').remove();

            // Track how often music is played
            var lastSent = new Date().getTime();
            $.each($('.mixframe'), function(i, mix) {
                SC.Widget(mix).bind(SC.Widget.Events.PLAY_PROGRESS, function(data) {
                    // only count it as an event every so often
                    if((new Date().getTime() - lastSent) > 60000) {
                        var mixId = $(mix).attr('src').match('/tracks/(\\d+)')[1];  // soundcloud id of the mix
                        var position = $('.mixframe').index(mix);  // what was its position in the list
                        _gaq.push(['_trackEvent', 'Mix', 'Playing', mixId, position]);

                        lastSent = new Date().getTime();
                    }
                });
            });
        }).error(function() {
            var message = $('<div>').addClass('error').html('Oh noes! An error occured fetching the top mixes. Please try again later');
            container.html(message);
            $('div.loading').remove();
        });
    };

    loadGenres(selectedGenres, page);

    // Handle scroll events for loading more entries
    var scrollReady = true;
    // throttle how often the scroll event is handled
    var scrollInterval = setInterval(function () { scrollReady = true; }, 500);

    $(window).bind('scroll', function () {
        if(!scrollReady) { return; }
        scrollReady = false;
        // when we get close to the bottom, pull in more entries
        if (($(this).scrollTop() + $(this).height()) >= ($(document).height() - 200)) {
            loadGenres(selectedGenres, ++page);
        }
    });
});