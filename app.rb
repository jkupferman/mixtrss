#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'dalli'
require 'soundcloud'

set :cache, Dalli::Client.new

SOUNDCLOUD_ID = ENV['SOUNDCLOUD_ID'] || YAML.load_file("config/soundcloud.yml")["id"]

FETCH_PAGE_SIZE = 200
RETURN_PAGE_SIZE = 5

AVAILABLE_GENRES = ["bass", "dance", "deep", "dubstep",
                    "electronic", "house", "mashup",
                    "progressive", "techno", "trance"]

get '/' do
  @genres = AVAILABLE_GENRES
  erb :index
end

get '/mixes/:genre/?:page?' do
  genre = (params[:genre] || 'mashup').strip.downcase
  # make sure no one is passing in any crazy genres
  genre = 'mashup' unless AVAILABLE_GENRES.include?(genre)

  page = (params[:page] || 0).to_i
  page = 0 if page < 0 || page > 20

  key = ['sc', 'tracks', genre].join('/')

  mixes = settings.cache.fetch(key) do
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)

    mixes = []
    5.times do |i|
      puts "Requesting #{genre} #{FETCH_PAGE_SIZE} #{i*FETCH_PAGE_SIZE}"
      tracks = client.get('/tracks',
                          :genres => genre,
                          :duration => {
                            :from => 1200000  # mixes must be a least 20 minutes
                          },
                          :order => 'hotness',
                          :limit => FETCH_PAGE_SIZE,
                          :offset => i * FETCH_PAGE_SIZE
                          )

      break if tracks.empty?
      mixes.concat(tracks.to_a.reject { |t| t.nil? })
    end

    mixes.sort_by { |t| t.playback_count || 0 }.reverse[0...100]
  end

  offset = page * RETURN_PAGE_SIZE
  mixes[offset...(offset + RETURN_PAGE_SIZE)].to_json
end
