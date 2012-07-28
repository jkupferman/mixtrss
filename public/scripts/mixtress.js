var BASE_URL = 'http://localhost:9393';

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
                Mixtress.collections.mixes = new Mixtress.Collection.Mixes([], {genre: genre, page: page});
                Mixtress.views.mixesview = new Mixtress.View.MixesView({collection: Mixtress.collections.mixes});
                Mixtress.collections.mixes.fetch();

                $('#container').empty().append(Mixtress.views.mixesview.render().el);
            },
            unknown: function(path) {
                console.log("CALLED UNKNOWN");
                console.log('ACTION is:', path);
                console.log(window.location.pathname);
            },
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
        console.log("MIXES FOR:", this.genre, this.page);
    },
    url: function() {
        return BASE_URL + '/mixes/' + this.genre + '/' + this.page;
    },
});

Mixtress.View.MixView = Backbone.View.extend({
    initialize: function() {
        this.template = _.template($('#mix-template').html());
    },
    render: function() {
        $(this.el).html(this.template(this.model.toJSON()));
        return this;
    },
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

$(Mixtress.initialize);
