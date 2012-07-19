#!/usr/bin/env ruby
require "rubygems"
require "dalli"
require "date"
require "json"
require "sinatra"
require "soundcloud"
require "yaml"

set :cache, Dalli::Client.new

SOUNDCLOUD_ID = ENV["SOUNDCLOUD_ID"] || YAML.load_file("config/soundcloud.yml")["id"]

FETCH_PAGE_SIZE = 200
PAGE_FETCH_COUNT = 20
RETURN_PAGE_SIZE = 5

AVAILABLE_GENRES = ["bass", "dance", "deep", "dubstep",
                    "electronic", "house", "mashup",
                    "progressive", "techno", "trance"]

get "/" do
  @genres = AVAILABLE_GENRES
  erb :index
end

get "/mixes/:genre/?:page?" do
  genre = (params[:genre] || "mashup").strip.downcase
  # make sure no one is passing in any crazy genres
  genre = "mashup" unless AVAILABLE_GENRES.include?(genre)

  page = (params[:page] || 0).to_i
  page = 0 if page < 0 || page > 20

  mixes = tracks(genre)

  offset = page * RETURN_PAGE_SIZE
  mixes[offset...(offset + RETURN_PAGE_SIZE)].to_json
end

def tracks(genre, force=false)
  # returns the top 100 tracks for the provided genre, sorted by freshness
  puts "Fetching #{genre}"
  genre_key = "topgenretracks/#{genre}"
  settings.cache.delete(genre_key) if force
  settings.cache.fetch(genre_key) do
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)

    mixes = PAGE_FETCH_COUNT.times.map do |i|
      puts "Requesting #{genre} #{FETCH_PAGE_SIZE} #{i*FETCH_PAGE_SIZE}"
      params = {
        :genres => genre,
        :duration => {
          :from => 1200000  # mixes must be a least 20 minutes
        },
        :order => "hotness",
        :limit => FETCH_PAGE_SIZE,
        :offset => i * FETCH_PAGE_SIZE
      }
      page_key = "page/" + params.map { |k, v| "#{k}=#{v}" }.sort.join(',')
      settings.cache.delete(page_key) if force
      settings.cache.fetch(page_key) do
        puts "Missed Cache. Fetching page #{page_key}"
        client.get("/tracks", params).to_a.reject { |t| t.nil? }
      end
    end
    mixes.flatten.select { |m| m }.sort_by { |t| freshness(t) }.reverse[0...100]
  end
end

def freshness track
  # returns a floating point number, representing the "freshness" of the track
  elapsed = (Date.today - Date.parse(track["created_at"]))
  elapsed = 1 if elapsed < 1
  plays = track["playback_count"]
  plays = 1 if plays.nil? || plays < 1
  plays.to_f / (elapsed ** 1.1)
end
