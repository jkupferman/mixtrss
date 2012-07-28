var BASE_URL = document.location.protocol + '//' + document.location.host;

// Use {{ mustache }} template delimiters to avoid ERB conflicts
_.templateSettings = { interpolate : /\{\{([\s\S]+?)\}\}/g };

Backbone.Application = function(attributes) {
    application = {
        // Singular, Capital Namespaces for class declarations
        Model: {}, View: {}, Collection: {},
        // plural, lowercase namespaces for instances
        models: {}, views: {}, collections: {},
        // global event dispatcher
        dispatcher: _.clone(Backbone.Events)
    };
    for (var property in attributes) {
        if (attributes.hasOwnProperty(property)) {
            application[property] = attributes[property];
        }
    }
    return application;
};

var Mixtress = new Backbone.Application({
    initialize: function() {
        Mixtress.Router = Backbone.Router.extend({
            routes: {
                '': 'home',
                '/': 'home',
                ':genre/:page': 'mixes',
                '*path': 'unknown'
            },
            home: function() {
                console.log("CALLED INDEX");
                // default the user to the first page of the "all" genre
                Mixtress.router.navigate('/all/0', true);
            },
            mixes: function(genre, page) {
                console.log("MIXES CALLED:", genre, page);

                Mixtress.views.navigationview = new Mixtress.View.NavigationView({genre: genre});
                $('#navigation').empty().append(Mixtress.views.navigationview.render().el);

                Mixtress.views.paginationview = new Mixtress.View.PaginationView({genre: genre, page: page});
                $('#pagination').empty().append(Mixtress.views.paginationview.render().el);

                Mixtress.collections.mixes = new Mixtress.Collection.Mixes([], {genre: genre, page: page});
                Mixtress.views.mixesview = new Mixtress.View.MixesView({collection: Mixtress.collections.mixes});
                Mixtress.collections.mixes.fetch();

                $('li.mix iframe').remove();  // clear out all the iframes for good measure
                $('#container').empty().append(Mixtress.views.mixesview.render().el);

                _gaq.push(['_trackPageview', Backbone.history.fragment]);
            },
            unknown: function(path) {
                console.log("CALLED UNKNOWN");
                console.log('ACTION is:', path);
                console.log(window.location.pathname);
            }
        });
        // Instantiate router
        Mixtress.router = new Mixtress.Router();
        Backbone.history.start();

        // Bind all the links whose hrefs start with a / to call internal navigation
        $(document).on('click', "a[href^='/']", function(event) {
            if(!event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
                event.preventDefault();
                var url = $(event.currentTarget).attr("href").replace(/^\//, "");
                Mixtress.router.navigate(url, true);
            }
        });
    }
});

Mixtress.Model.Mix = Backbone.Model.extend({
    defaults: {
        uri: '',
        score: 0
    }
});

Mixtress.Collection.Mixes = Backbone.Collection.extend({
    model: Mixtress.Model.Mix,
    initialize: function(models, options) {
        this.genre = options.genre;
        this.page = options.page;
    },
    url: function() {
        return BASE_URL + '/mixes/' + this.genre + '/' + this.page;
    }
});

Mixtress.View.MixView = Backbone.View.extend({
    tagName: 'li',
    className: 'mix',
    initialize: function() {
        this.template = _.template($('#mix-template').html());
    },
    render: function() {
        $(this.el).html(this.template(this.model.toJSON()));
        return this;
    }
});

Mixtress.View.MixesView = Backbone.View.extend({
    tagName: 'section',
    className: 'container',
    initialize: function() {
        _.bindAll(this, 'render');
        this.template = _.template($('#mixes-template').html());
        this.collection.bind('reset', this.render);
    },
    render: function() {
        var collection = this.collection;
        $(this.el).html(this.template({}));

        var $mixes = this.$('.mixes');
        collection.each(function(mix, i) {
            var view = new Mixtress.View.MixView({
                model: mix,
                collection: collection
            });
            $mixes.append(view.render().el);
        });
        return this;
    }
});

Mixtress.View.NavigationView = Backbone.View.extend({
    tagName: 'section',
    className: 'navigation',
    initialize: function(options) {
        _.bindAll(this, 'render');
        this.template = _.template($('#navigation-template').html());
        this.selectedGenre = options.genre;
    },
    render: function() {
        var that = this;
        $(this.el).html(this.template({}));

        var $genres = this.$('.genres');
        _(AVAILABLE_GENRES).each(function(genre, i) {
            var view = new Mixtress.View.NavigationEntryView({
                genre: genre,
                isLast: (i == AVAILABLE_GENRES.length - 1),
                isSelected: (that.selectedGenre == genre)
            });

            $genres.append(view.render().el);
        });

        return this;
    }
});

Mixtress.View.NavigationEntryView = Backbone.View.extend({
    tagName: 'li',
    className: 'genre',
    initialize: function(options) {
        _.bindAll(this, 'render');
        this.template = _.template($('#navigation-entry-template').html());
        this.genre = options.genre;
        this.isLast = options.isLast;
        this.isSelected = options.isSelected;
    },
    render: function() {
        var title = this.genre.charAt(0).toUpperCase() + this.genre.substring(1).toLowerCase();
        var separator = this.isLast ? "" : "/";
        var classes = this.isSelected ? "selected" : "";
        $(this.el).html(this.template({
            genre: this.genre,
            title: title,
            separator: separator,
            classes: classes
        }));
        return this;
    }
});

Mixtress.View.PaginationView = Backbone.View.extend({
    tagName: 'section',
    className: 'pagination',
    events: {
        'click a': 'navigate'
    },
    initialize: function(options) {
        _.bindAll(this, 'render');
        this.template = _.template($('#pagination-template').html());
        this.selectedGenre = options.genre;
        this.selectedPage = parseInt(options.page);
    },
    render: function() {
        $(this.el).html(this.template({
            genre: this.selectedGenre,
            previousPage: this.selectedPage - 1,
            previousClasses: this.selectedPage == 0 ? "hidden" : "",
            nextPage: this.selectedPage + 1,
            nextClasses: this.selectedPage == 9 ? "hidden" : ""
        }));

        return this;
    },
    navigate: function() {
        $('body').animate({scrollTop: 0});
    }
});

$(Mixtress.initialize);
