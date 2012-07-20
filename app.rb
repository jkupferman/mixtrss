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

get "/mixes/:genres/?:page?" do
  genres = params[:genres].to_s.strip.downcase
  genres = genres.split(',').select { |g| AVAILABLE_GENRES.include?(g) }
  # make sure no one is passing in any crazy genres
  genres = AVAILABLE_GENRES if genres.empty?

  page = (params[:page] || 0).to_i
  page = 0 if page < 0 || page > 20

  combined_mixes = genres.map { |genre| tracks(genre) }.flatten.uniq { |m| m[:uri] }

  ordered_mixes = combined_mixes.sort_by { |t| t[:score] }.reverse

  offset = page * RETURN_PAGE_SIZE
  ordered_mixes[offset...(offset + RETURN_PAGE_SIZE)].to_json
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
      client.get("/tracks", params).to_a.reject { |t| t.nil? }
    end
    mixes.flatten.select { |m| m }.sort_by { |t| freshness(t) }.reverse[0...100].map { |e| { :uri => e['uri'], :score => freshness(e) } }
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
