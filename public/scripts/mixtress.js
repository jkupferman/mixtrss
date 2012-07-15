$(function() {
    var container = $('#container');

    // get the currently selected genre
    var genre = window.location.hash;
    var page = 0;
    if(genre.indexOf('/') >= 0) {
        // check if the genre has a slash, and thus a page number
        var tokens = genre.split('/');
        genre = tokens[0];
        page = tokens[1];
    } else {
        genre = window.location.hash || 'mashup';
    }

    if(genre.indexOf('#') == 0) {
        genre = genre.slice(1); // remove the leading hash if there is one
    }

    var genres = {};
    // keep handles to the genres by name
    $.each($('ul.genres li'), function(i, genre) {
        genre = $(genre);
        genres[genre.data('genre')] = genre;
    });

    // handle users selecting a genre
    $('ul.genres li').click(function() {
        genre = $(this).data('genre');
        page = 0;
        loadGenre(genre, page);
    });

    var loadGenre = function(genre, pageNum) {
        if(pageNum > 20) { return; }
        console.log("LOADING:", genre, pageNum);
        window.location.hash = genre + '/' + pageNum;

        if(pageNum == 0) {
            // when its a new genre we should clear out the entries
            container.empty();
        }

        // select the appropriate nav element
        $('ul.genres li').removeClass('selected');
        genres[genre].addClass('selected');

        var url = '/mixes/' + genre + '/' + pageNum;
        $.getJSON(url, function(data) {
            var mixes = $('<ul>').addClass('mixes').addClass(genre).addClass(pageNum);
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
        }).error(function() {
            var message = $('<div>').addClass('error').html('Oh noes! An error occured fetching the top mixes. Please try again later');
            container.html(message);
        });
    };

    loadGenre(genre, page);


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
            loadGenre(genre, page);
        }
    });
});