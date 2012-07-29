#!/usr/bin/env ruby
require "rubygems"
require './app'

forced = ARGV && ARGV[0].to_s.downcase() == 'force'
puts "Refreshing tracks. Forced = #{forced}"

threads = []
AVAILABLE_GENRES.each do |genre|
  threads << Thread.new do |t|
    attempts = 0
    cache = {} # per-thread cache so we don't re-fetch pages when failure occur
    begin
      attempts += 1
      puts "Getting #{genre} attempt #{attempts}"
      tracks(genre, force=(forced && (attempts == 1)), page_cache=cache)
    rescue Soundcloud::ResponseError => e
      sleep attempts ** attempts
      puts "Response Error! #{genre} #{e.response}"
      retry if attempts < 10
    end
  end
end

threads.each { |t| t.join }

puts "Done refreshing tracks"
