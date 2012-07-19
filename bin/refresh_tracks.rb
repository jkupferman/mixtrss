#!/usr/bin/env ruby
require "rubygems"
require './app'

puts "Refreshing tracks"
AVAILABLE_GENRES.each do |genre|
  attempts = 0
  begin
    attempts += 1
    puts "Getting #{genre} attempt #{attempts}"
    tracks(genre, force=true)
  rescue Soundcloud::ResponseError => e
    sleep 3
    puts "Response Error! #{e.inspect}"
    retry if attempts < 5
  end
end

puts "Done refreshing tracks"
