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
RETURN_PAGE_SIZE = 10

AVAILABLE_GENRES = ["all", "bass", "dance", "deep", "dubstep",
                    "electronic", "house", "mashup",
                    "progressive", "techno", "trance"]

get "/" do
  @genres = AVAILABLE_GENRES
  erb :index
end

get "/mixes/:genres/?:page?" do
  genres = params[:genres].to_s.strip.downcase
  # make sure no one is passing in any crazy genres
  genres = genres.split(',').select { |g| AVAILABLE_GENRES.include?(g) }
  genres = AVAILABLE_GENRES if genres.empty?

  page = (params[:page] || 0).to_i
  return [].to_json if page < 0 || page > 10

  combined_mixes = genres.map { |genre| tracks(genre) }.flatten.uniq { |m| m[:uri] }

  ordered_mixes = combined_mixes.sort_by { |t| t[:score] }.reverse

  offset = page * RETURN_PAGE_SIZE
  ordered_mixes[offset...(offset + RETURN_PAGE_SIZE)].to_json
end

post "/contact" do
  require 'pony'
  Pony.mail(:from => params[:name] + "<" + params[:email] + ">",
            :to => 'jmkupferman+mixtress@gmail.com',
            :subject => "Mixtress contact from #{params[:name]}",
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

def tracks(genre, force=false, page_cache={})
  # returns the top 100 tracks for the provided genre, sorted by freshness
  puts "Fetching #{genre}"
  genre_key = "topgenretracks/#{genre}"
  settings.cache.delete(genre_key) if force
  settings.cache.fetch(genre_key) do
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)

    # Have all fetch significantly more since it has a lot more non-mixes
    pages_to_fetch = genre == "all" ? PAGE_FETCH_COUNT * 2 : PAGE_FETCH_COUNT

    mixes = []
    pages_to_fetch.times do |i|
      puts "Requesting #{genre} #{FETCH_PAGE_SIZE} #{i*FETCH_PAGE_SIZE}"
      params = {
        :duration => {
          :from => 1200000  # mixes must be a least 20 minutes
        },
        :order => "hotness",
        :limit => FETCH_PAGE_SIZE,
        :offset => i * FETCH_PAGE_SIZE
      }
      params[:genres] = genre unless genre == "all"

      page_key = "page/#{params}"

      begin
        tracks = page_cache[page_key] || client.get("/tracks", params).to_a.reject { |t| t.nil? }
      rescue Crack::ParseError
        # TODO: Why are these happening?
        puts "ParseError! #{genre} #{params}"
        tracks = []
      end
      if tracks && tracks.any?
        tracks.select! { |t| is_mix? t }
        page_cache[page_key] = tracks
        mixes.concat(tracks)
      else
        break # we've reached the end of that genre
      end
    end
    top_mixes = mixes.flatten.sort_by { |t| freshness(t) }.reverse[0...100]
    # filter out any extraneous data so the key will fit in memcached
    top_mixes.map { |e| { :uri => e['uri'], :score => freshness(e), :title => e['title'] } }
  end
end

def is_mix? track
  # Given a track this function does its best to determine if it's actually
  # a music mix (instead of say a gaming podcast or interview)
  return false unless track

  type = track['track_type'].to_s.downcase
  return false if ["spoken"].include? type

  # filter out some known non-music accounts
  userid = (track['user'] || {})['id'].to_s
  return false if ["15772169", "16890685", "8211472", "8717773", "21184161", "8396105", "19810996", "22244447", "13939351", "22234834", "20023000", "22343246", "15559691", "5170489", "13881787", "8937813", "2604591", "7077355", "10965205", "23221241", "22314338", "18334213", "917197", "20626177"].include? userid

  genre = track['genre'].to_s.downcase
  return false if ["comedy", "film", "criatividade", "humor", "sport", "comedia", "morning show", "technology", "interview", "spoken", "tech", "mma"].include? genre

  tags = track['tag_list'].to_s.downcase
  ["empire podcast", "comedy", "humor", "game", "edgefiles"].each do |tag|
    return false if tags.include? tag
  end

  true
end

def freshness track
  # returns a floating point number, representing the "freshness" of the track
  elapsed = (Date.today - Date.parse(track["created_at"]))
  elapsed = 1 if elapsed < 1
  plays = track["playback_count"]
  plays = 1 if plays.nil? || plays < 1
  plays.to_f / (elapsed ** 1.2)
end
