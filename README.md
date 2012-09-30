# mixtrss
### bringing you the best dj mixes on the web, each and every day

## check it out
mixtrss is currently running at http://mixtrss.com/

## run it

mixtrss is a Sinatra app on ruby 1.9.2 that uses memcached as its data store.

     # clone it
     git clone git@github.com:jkupferman/mixtrss.git

     # get up in it
     cd mixtrss

     # install da gems
     bundle

     # add in your soundcloud developer id (this is required)
     echo "id: {{THIS_IS_YOUR_SOUNDCLOUD_ID}}" > config/soundcloud.yml
     
     # startup memcached
     memcached -m 64 -d

     # pull in the mixes (this takes a few minutes)
     ruby bin/refresh_tracks.rb

     # run it
     shotgun app.rb

     # open in your browser
     open http://localhost:9393

Created by [@jkupferman](http://twitter.com/jkupferman)