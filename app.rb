#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'dalli'
require 'soundcloud'

set :cache, Dalli::Client.new

SOUNDCLOUD_CONFIG = YAML.load_file("config/soundcloud.yml")

PAGE_SIZE = 100

get '/' do
  'Hello World'
end

get '/mixes' do
  genre = 'mashup'
  key = ['tracks', genre].join('/')

  mixes = settings.cache.fetch(key) do
    client = Soundcloud.new(:client_id => SOUNDCLOUD_CONFIG["id"])

    mixes = []
    2.times do |i|
      tracks = client.get('/tracks',
                          :genres => genre,
                          :duration => {
                            :from => 1200000  # mixes must be a least 20 minutes
                          },
                          :order => 'hotness',
                          :limit => PAGE_SIZE,
                          :offset => i * PAGE_SIZE
                          )

      break if tracks.empty?
      mixes.concat(tracks.to_a.reject { |t| t.nil? })
    end

    mixes.sort_by { |t| t.playback_count || 0 }.reverse
  end

  mixes.to_json
end
