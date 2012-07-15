$(function() {
    var container = $('#container');
    var genres = {};
    // keep handles to the genres by name
    $.each($('ul.genres li'), function(i, genre) {
        genre = $(genre);
        genres[genre.data('genre')] = genre;
    });

    // get the currently selected genre
    var genre = window.location.hash || 'mashup';
    if(genre.indexOf('#') == 0) {
        genre = genre.slice(1); // remove the leading hash if there is one
    }

    // handle users selecting a genre
    $('ul.genres li').click(function() {
        loadGenre($(this).data('genre'));
    });

    var loadGenre = function(genre) {
        container.empty(); // clear it out
        // select the appropriate element
        $('ul.genres li').removeClass('selected');
        genres[genre].addClass('selected');

        var url = '/mixes/' + genre;
        $.getJSON(url, function(data) {
            var mixes = $('<ul>').addClass('mixes').addClass(genre);
            $.each(data, function(i, mix) {
                console.log(mix);
                var mixEl = $('<li>').addClass('mix').addClass(mix.id);
                var iframeEl = $('<iframe>').attr('width', '100%')
                                         .attr('height', 166)
                                         .attr('scrolling', 'no')
                                         .attr('frameborder', 'no');
                var url = 'http://w.soundcloud.com/player/?url=' + mix.uri + '&show_artwork=true';
                iframeEl.attr('src', url);
                mixEl.html(iframeEl);
                mixes.append(mixEl);
            });
            container.empty().append(mixes);
            window.location.hash = genre;
        }).error(function() {
            container.html('Oh noes! An error occured fetching the top mixes. Please try again later');
        });
    };

    loadGenre(genre);
});