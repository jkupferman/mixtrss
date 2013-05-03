#!/usr/bin/env ruby
require "rubygems"
require './app'

puts "Refreshing tracks"

# Skip 1/3 of these so we don't go over the heroku limit
skip = ARGV[0] == 'production' && Time.now.hour % 3 > 0

if skip
  print "Skipped!"
else
  refresh_tracks()
end

puts "Done refreshing tracks"
