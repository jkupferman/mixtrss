#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'dalli'
require 'soundcloud'

set :cache, Dalli::Client.new

SOUNDCLOUD_ID = ENV['SOUNDCLOUD_ID'] || YAML.load_file("config/soundcloud.yml")["id"]

PAGE_SIZE = 200

AVAILABLE_GENRES = ["bass", "dance", "deep", "dubstep",
                    "electronic", "house", "mashup",
                    "progressive", "techno", "trance"]

get '/' do
  @genres = AVAILABLE_GENRES
  erb :index
end

get '/mixes/:genre' do
  genre = params[:genre].strip.downcase || 'mashup'
  # make sure no one is passing in any crazy genres
  genre = 'mashup' unless AVAILABLE_GENRES.include?(genre)

  key = ['sc', 'tracks', genre].join('/')

  mixes = settings.cache.fetch(key) do
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)

    mixes = []
    5.times do |i|
      puts "Requesting #{genre} #{PAGE_SIZE} #{i*PAGE_SIZE}"
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

    mixes.sort_by { |t| t.playback_count || 0 }.reverse[0...100]
  end

  mixes[0...5].to_json
end
