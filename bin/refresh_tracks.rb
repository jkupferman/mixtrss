#!/usr/bin/env ruby
require "rubygems"
require './app'

forced = ARGV && ARGV[0].to_s.downcase() == 'force'
puts "Refreshing tracks. Forced = #{forced}"
threads = []
AVAILABLE_GENRES.each do |genre|
  threads << Thread.new do |t|
    attempts = 0
    begin
      attempts += 1
      puts "Getting #{genre} attempt #{attempts}"
      tracks(genre, force=(forced && (attempts == 1)))
    rescue Soundcloud::ResponseError => e
      sleep 3
      puts "Response Error! #{e.inspect}"
      retry if attempts < 5
    end
  end
end

threads.each { |t| t.join }

puts "Done refreshing tracks"
