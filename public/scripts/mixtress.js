$(function() {
    var container = $('#container');
    var loadingEl = $('<div>').addClass('loading').html($('<img>').attr('src', '/images/blocks.gif'));

    var genresEl = {};
    // keep handles to the genres by name
    $.each($('ul.genres li'), function(i, genre) {
        genre = $(genre);
        genresEl[genre.data('genre')] = genre;
    });

    var hash = window.location.hash;
    if(hash.indexOf('#') == 0) {
        hash = hash.slice(1); // remove the leading hash if there is one
    }

    var genres = [];
    var page = 0;
    if(hash.indexOf('/') >= 0) {
        // check if the genre has a slash, and thus a page number
        var tokens = hash.split('/');
        genres = tokens[0].split(',');
        page = tokens[1];
    } else {
        genres = hash.split(',');
    }

    if(genres.length < 1 || (genres.length == 1 && genres[0] == '')) {
        // default to all genres on
        genres = $.map(genresEl, function(v, k) { return k; });
    }

    // handle users selecting a genre
    $('ul.genres li').click(function() {
        var genre = $(this).data('genre');
        if($(this).hasClass('selected')) {
            genres.splice(genres.indexOf(genre), 1);
        } else {
            genres.push(genre);
        }
        page = 0;
        loadGenres(genres, page);
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
            genresEl[genre].addClass('selected');
        });

        // add in the loading gif
        container.append(loadingEl);

        var url = '/mixes/' + urlPath;
        $.getJSON(url, function(data) {
            var mixes = $('<ul>').addClass('mixes').addClass(genres).addClass(pageNum);
            container.append(mixes);
            $.each(data, function(i, mix) {
                var mixEl = $('<li>').addClass('mix').addClass(mix.id);
                var iframeEl = $('<iframe>').attr('width', '100%')
                                         .attr('height', 166)
                                         .attr('scrolling', 'no')
                                         .attr('frameborder', 'no');
                var url = 'http://w.soundcloud.com/player/?url=' + mix.uri + '&show_artwork=true&show_comments=false';
                iframeEl.attr('src', url);
                mixEl.html(iframeEl);
                mixes.append(mixEl);
            });
            $('div.loading').remove();
        }).error(function() {
            var message = $('<div>').addClass('error').html('Oh noes! An error occured fetching the top mixes. Please try again later');
            container.html(message);
            $('div.loading').remove();
        });
    };

    loadGenres(genres, page);

    // Handle scroll events for loading more entries
    var canScroll = true;
    // throttle how often the scroll event is handled
    var scrollInterval = setInterval(function () { canScroll = true; }, 500);

    $(window).bind('scroll', function () {
        if(!canScroll) { return; }
        canScroll = false;
        // when we get close to the bottom, pull in more entries
        if ($(this).scrollTop() + $(this).height() >= ($(document).height() - 200)) {
            page++;
            loadGenres(genres, page);
        }
    });

    // Keep track of how long people are listening for
    // FIXME: This should use actual soundcloud events
    setInterval(function() { _gaq.push(['_trackEvent', 'Mix', 'Listen']); }, 60000);
});