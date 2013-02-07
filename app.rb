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
BLACKLIST = YAML.load_file("config/blacklist.yml")['blacklist']

FETCH_PAGE_SIZE = 200
PAGE_FETCH_COUNT = 40
RETURN_PAGE_SIZE = 10

AVAILABLE_GENRES = ["all", "bass", "dance", "deep",
                    "drum & bass", "dubstep",
                    "electro", "house", "mashup",
                    "techno", "trance", "trap"]

get "/" do
  @genres = AVAILABLE_GENRES
  erb :index
end

get "/mixes/:genre/:page" do
  content_type 'application/json'

  genre = params[:genre].to_s.strip.downcase
  genre = "all" unless AVAILABLE_GENRES.include?(genre)

  page = (params[:page] || 0).to_i

  offset = page * RETURN_PAGE_SIZE
  mixes_for_genre(genre)[offset...(offset + RETURN_PAGE_SIZE)].to_json
end

post "/feedback" do
  require 'pony'
  Pony.mail(:from => params[:name] + "<" + params[:email] + ">",
            :to => 'jmkupferman+mixtress' + '@' + 'gmail.com',
            :subject => "Mixtress feedback from #{params[:name]}",
            :body => params[:message],
            :port => '587',
            :via => :smtp,
            :via_options => {
              :address              => 'smtp.gmail.com',
              :port                 => '587',
              :enable_starttls_auto => true,
              :user_name            => ENV['GMAIL_SMTP_USER'],
              :password             => ENV['GMAIL_SMTP_PASSWORD'],
              :authentication       => :plain,
              :domain               => 'localhost.localdomain'
            })
  redirect '/'
end

def mixes_for_genre genre
  # fetches the precomputed mixes from memcache
  settings.cache.get(genre_key(genre)) || []
end

def genre_key genre
  "toptracks/#{genre}"
end

def fetch_tracks page, genre=nil
  puts "Requesting #{FETCH_PAGE_SIZE} #{page*FETCH_PAGE_SIZE}"
  params = {
    :duration => {
      :from => 1200000  # mixes must be a least 20 minutes long
    },
    :order => "hotness",
    :limit => FETCH_PAGE_SIZE,
    :offset => page * FETCH_PAGE_SIZE
  }

  attempts = 0
  begin
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
    client.get("/tracks", params).to_a.select { |t| t && is_mix?(t) }
  rescue Soundcloud::ResponseError
    puts "Soundcloud::ResponseError - #{e.response}"
    sleep(1)
    attempts += 1
    if attempts < 20
      retry
    else
      []
    end
  rescue Crack::ParseError
    # TODO: Why are these happening?
    puts "ParseError! #{params}"
    []
  end
end

def refresh_tracks
  tracks = []
  PAGE_FETCH_COUNT.times do |i|
    tracks.concat(fetch_tracks(i))
  end

  tracks.each do |track|
    # set the tags as a list on each track
    track["tags"] = extract_tags(track) << track["genre"].to_s.downcase
  end

  AVAILABLE_GENRES.each do |genre|
    filtered_tracks = tracks.uniq { |t| t['uri'] }
    filtered_tracks = tracks.select { |t| t["tags"].include? genre } if genre != "all"

    top_tracks = filtered_tracks.sort_by { |t| freshness(t) }.reverse[0...100]
    # filter out any extraneous data so the key will fit in memcached
    result = top_tracks.map do |e|
      { :uri => e['uri'],
        :score => freshness(e),
        :title => e['title'],
        :downloadable => e['downloadable']
      }
    end
    puts "Found #{result.length} tracks for #{genre}"
    settings.cache.set(genre_key(genre), result)
  end
end

def is_mix? track
  # Given a track this function does its best to determine if it's actually
  # a music mix (instead of say a gaming podcast or interview)
  return false unless track

  type = track['track_type'].to_s.downcase
  return false if BLACKLIST['track_type'].include? type

  # filter out some known non-music accounts
  userid = (track['user'] || {})['id']
  return false if userid && BLACKLIST['userid'].include?(userid.to_i)

  genre = track['genre'].to_s.downcase
  return false if BLACKLIST['genre'].include? genre

  tags = track['tag_list'].to_s.downcase
  BLACKLIST['tag'].each do |tag|
    return false if tags.include? tag
  end

  true
end

def extract_tags track
  track['tag_list'].to_s.downcase.scan(/"([^"]*)"|(\w+)/).flatten.select { |t| t }
end

def freshness track
  # returns a floating point number, representing the "freshness" of the track
  elapsed = (Date.today - Date.parse(track["created_at"]))
  elapsed = 1 if elapsed < 1
  plays = track["playback_count"]
  plays = 1 if plays.nil? || plays < 1
  plays.to_f / (elapsed ** 1.2)
end
