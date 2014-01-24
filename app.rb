#!/usr/bin/env ruby
require "rubygems"
require "dalli"
require "memcachier"
require "date"
require "json"
require "sinatra"
require "soundcloud"
require "yaml"
require "open-uri"

set :cache, Dalli::Client.new
set :static_cache_control, [:public, max_age: 60 * 60 * 24 * 365]

SOUNDCLOUD_ID = ENV["SOUNDCLOUD_ID"] || YAML.load_file("config/soundcloud.yml")["id"]
BLACKLIST = YAML.load_file("config/blacklist.yml")['blacklist']

FETCH_PAGE_SIZE = 200
PAGE_FETCH_COUNT = 40
RETURN_PAGE_SIZE = 10
MINIMUM_TRACK_DURATION = 1200000
EXPLORE_CATEGORIES = ["Popular%2BMusic", "dubstep", "house", "electronic", "pop", "techno", "rock", "reggae"]

AVAILABLE_GENRES = ["all", "bass", "dance", "deep",
                    "drum & bass", "dubstep",
                    "electro", "house", "mashup",
                    "techno", "trance", "trap"]

get "/:genre?/?:page?" do
  genre, page = genre_and_page params[:genre], params[:page]
  @mixes = mixes(genre, page)
  @description = description @mixes, genre
  @canonical = canonical genre, page
  @title = title genre, page

  erb :index
end

get "/mixes/:genre/:page" do
  content_type 'application/json'

  genre, page = genre_and_page params[:genre], params[:page]

  mixes(genre, page).to_json
end

def genre_and_page genre, page
  # sanitize the incoming genre and page values to ensure they are valid
  genre = genre.to_s.strip.downcase
  genre = AVAILABLE_GENRES.include?(genre) ? genre : "all"

  page = (page || 0).to_i

  [genre, page]
end

def mixes genre, page
  offset = page * RETURN_PAGE_SIZE
  mixes_for_genre(genre)[offset...(offset + RETURN_PAGE_SIZE)]
end

def title genre, page
  if genre == "all"
    "Mixtrss - the best mixes on Soundcloud"
  else
    "#{genre.capitalize} mixes | Mixtrss"
  end
end

def description mixes, genre
  artists = mixes.map { |m| m[:artist] }[0...4].join(", ")

  display_genre = (genre == 'all') ? 'electro' : genre
  "Listen to the best #{display_genre} mixes and dj sets on the web. Mixes by #{artists}."
end

def canonical genre, page
  "http://mixtrss.com/#{URI.escape(genre)}/#{page}"
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

def recent_tracks_key
  "recenttracks"
end

def fetch_tracks page, genre=nil, tag=nil
  puts "#{Time.now}: Requesting #{FETCH_PAGE_SIZE} #{page*FETCH_PAGE_SIZE} tag:#{tag} genre:#{genre}"
  params = {
    :duration => {
      :from => MINIMUM_TRACK_DURATION
    },
    :order => "hotness",
    :limit => FETCH_PAGE_SIZE,
    :offset => page.to_i * FETCH_PAGE_SIZE
  }
  params[:genres] = genre if genre
  params[:tags] = tag if tag

  attempts = 0
  begin
    client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
    client.get("/tracks", params).to_a.select { |t| t && is_mix?(t) }
  rescue Soundcloud::ResponseError, Timeout::Error, Errno::ECONNRESET => e
    puts "Soundcloud::ResponseError - #{e} for #{page} #{genre} #{tag}"
    if e.respond_to?(:message)
      puts "Message: #{e.response.code} - #{e.message}"
    end
    attempts += 1
    sleep(attempts * 2)
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

def track_by_id track_id
  client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
  begin
    track = client.get("/tracks/#{track_id}")
    track if track && is_mix?(track)
  rescue Soundcloud::ResponseError, Timeout::Error, Errno::ECONNRESET => e
    puts "Soundcloud::ResponseError - #{e} #{track_id}"
  end
end

def tracks_by_ids track_ids
  # multi-get for tracks, a maximum of 50 track ids can be fetched at once
  client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
  client.get("/tracks", {:ids => track_ids.join(",")}).select { |t| t && is_mix?(t) }
end

def explore_track_ids
  # returns the list of track ids that are featured in soundclouds explore section
  track_ids = []
  EXPLORE_CATEGORIES.each do |category|
    # soundcloud exposes explore via their web api which isnt accessible via the gem, so grab it from the url directly
    url = "https://api-web.soundcloud.com/explore/#{category}?tag=uniform-time-decay-experiment%3A1%3A1389973574&limit=100&offset=0&linked_partitioning=1"
    begin
      json = JSON.parse(open(url).read)
    rescue OpenURI::HTTPError
      puts "Error fetching explore category #{category}"
    end
    track_ids.concat json['tracks'].map { |t| t['id'].to_s }
  end
  track_ids.uniq
end

def recent_track_ids
  settings.cache.get(recent_tracks_key) || []
end

def refresh_tracks
  tracks = []
  threads = []
  AVAILABLE_GENRES.each do |genre|
    threads << Thread.new do
      PAGE_FETCH_COUNT.times do |i|
        # have each thread sleep for a bit to avoid stampeding the soundcloud api
        sleep(rand() * 20)
        if genre == "all"
          tracks.concat(fetch_tracks(i))
        elsif i < 10
          # grab mixes for the specific genre to make sure fill them out
          # only grab a few pages since most genres aren't very deep
          tracks.concat(fetch_tracks(i, genre, nil))
          tracks.concat(fetch_tracks(i, nil, genre))
        end
      end
    end
  end
  threads.each { |t| t.join }

  puts "Fetching explore and recent tracks"
  # include the tracks from the explore section
  # also include recently popular tracks to keep a longer history
  (explore_track_ids + recent_track_ids).sort.uniq.each_slice(50) do |track_ids|
    tracks.concat tracks_by_ids(track_ids)
  end

  tracks.uniq! { |t| t['uri'] }

  tracks.each do |track|
    track["tags"] = (track['tag_list'].to_s << " " << track["genre"].to_s).downcase
    track["freshness"] = freshness(track)
  end

  AVAILABLE_GENRES.each do |genre|
    genre_regex = /\b#{genre}\b/
    filtered_tracks = tracks.select { |t| genre == "all" || genre_regex =~ t["tags"] }

    top_tracks = filtered_tracks.sort_by { |t| t['freshness'] }.reverse[0...100]
    # filter out any extraneous data so the key will fit in memcached
    result = top_tracks.map do |e|
      { :uri => e['uri'],
        :score => e['freshness'],
        :title => e['title'],
        :permalink => e['permalink_url'],
        :artist => e['user']['username'],
        :downloadable => e['downloadable'],
        :created_at => Time.parse(e['created_at']).getutc.iso8601
      }
    end
    puts "Found #{result.length} tracks for #{genre}"
    settings.cache.set(genre_key(genre), result)
  end

  recent_tracks = tracks.sort_by { |t| -t['freshness'] }[0...500].map { |t| t['id'].to_s }
  settings.cache.set(recent_tracks_key, recent_tracks)
end

def is_mix? track
  # Given a track this function does its best to determine if it's actually
  # a music mix (instead of say a gaming podcast or interview)
  return false unless track

  # it better be long enough...
  return false if track['duration'] < MINIMUM_TRACK_DURATION

  # check the track for any known blacklisted values (e.g. non-music accounts, bad genres)
  type = track['track_type'].to_s.downcase
  return false if BLACKLIST['track_type'].include? type

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

def freshness track
  # returns a floating point number, representing the "freshness" of the track
  elapsed = (Date.today - Date.parse(track["created_at"]))
  elapsed = 1 if elapsed < 1
  plays = track["playback_count"]
  plays = 1 if plays.nil? || plays < 1
  plays.to_f / (elapsed ** 1.2)
end
