#!/usr/bin/env ruby
require "rubygems"
require './app'

forced = ARGV && ARGV[0].to_s.downcase() == 'force'
puts "Refreshing tracks. Forced = #{forced}"

refresh_tracks()

puts "Done refreshing tracks"
