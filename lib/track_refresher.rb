require "dalli"
require "memcachier"
require "date"
require "json"
require "soundcloud"
require "yaml"
require "open-uri"
require "./lib/common"


class TrackRefresher
  SOUNDCLOUD_ID = ENV["SOUNDCLOUD_ID"] || YAML.load_file("config/soundcloud.yml")["id"]
  BLACKLIST = YAML.load_file("config/blacklist.yml")['blacklist']

  FETCH_PAGE_SIZE = 200
  PAGE_FETCH_COUNT = 40
  MINIMUM_TRACK_DURATION = 1200000

  AVAILABLE_GENRES = Common::AVAILABLE_GENRES

  def initialize
    @cache = Dalli::Client.new
  end

  def refresh! fast=false
    tracks = recently_popular_tracks
    # searching takes a while, so don't do them in fast mode
    tracks += tracks_from_search unless fast

    puts "Ordering and bucketing tracks..."
    tracks.uniq! { |t| t['uri'].strip.gsub("https:", "http:") }

    tracks.each do |track|
      # combine and normalize tags and genres into one field
      track["tags"] = (track['tag_list'].to_s << " " << track["genre"].to_s).downcase
      track["freshness"] = freshness(track)
    end

    tracks.sort_by! { |t| -t['freshness'] }

    # store the top tracks for each genre
    AVAILABLE_GENRES.each do |genre|
      genre_regex = /\b#{genre}\b/
      top_tracks_by_genre = tracks.select { |t| genre == "all" || genre_regex =~ t["tags"] }[0...100]

      # filter out any extraneous data so it will fit within the memcached size limit
      filtered_tracks = top_tracks_by_genre.map do |e|
        {
          uri: e['uri'],
          score: e['freshness'],
          title: e['title'],
          permalink: e['permalink_url'],
          artist: e['user']['username'],
          downloadable: e['downloadable'],
          created_at: Time.parse(e['created_at']).getutc.iso8601
        }
      end
      puts "Found #{filtered_tracks.length} tracks for #{genre}"
      @cache.set(Common.genre_key(genre), filtered_tracks)
    end

    @cache.set(recent_tracks_key, tracks[0...10000].map { |t| t['id'].to_s })

    puts "All Done!"
  end

  def tracks_from_search
    # scour the soundcloud search api to get all the mixes we can find. this method takes about five minutes to run
    combinations = Queue.new
    PAGE_FETCH_COUNT.times do |i|
      combinations << [i, nil, nil]
      AVAILABLE_GENRES.each do |genre|
        next if genre == "all"
        # grab mixes for the specific genre to make sure fill them out
        # only grab a few pages since most genres aren't very deep
        combinations << [i, genre, nil] if i < 10
        combinations << [i, nil, genre] if i < 10
      end
    end

    tracks = []
    threads = []
    15.times do |i|
      threads << Thread.new do
        # have each thread sleep for a bit to avoid stampeding the soundcloud api
        sleep(rand() * 20)
        while combinations.length > 0
          combo = combinations.pop
          tracks.concat(fetch_tracks(*combo)) if combo.length > 0
        end
      end
    end
    threads.each { |t| t.join }

    tracks
  end

  def fetch_tracks page, genre=nil, tag=nil
    puts "#{Time.now}: Requesting #{FETCH_PAGE_SIZE} #{page*FETCH_PAGE_SIZE} tag:#{tag} genre:#{genre}"
    params = {
      duration: { from: MINIMUM_TRACK_DURATION },
      order: "hotness",
      limit: FETCH_PAGE_SIZE,
      offset: page.to_i * FETCH_PAGE_SIZE
    }
    params[:genres] = genre if genre
    params[:tags] = tag if tag

    attempts = 0
    begin
      client.get("/tracks", params).to_a.select { |t| t && is_mix?(t) && t["playback_count"].to_i > 20 }
    rescue Soundcloud::ResponseError, Timeout::Error, Errno::ECONNRESET, JSON::ParserError => e
      puts "Soundcloud::ResponseError - #{e} for #{page} #{genre} #{tag}"
      if e.respond_to?(:message) && e.respond_to?(:response)
        puts "Message: #{e.response.code} - #{e.message}"
      end
      attempts += 1
      sleep(attempts * 2)
      if attempts < 20
        retry
      else
        []
      end
    end
  end

  def track_by_id track_id
    begin
      track = client.get("/tracks/#{track_id}")
      track if track && is_mix?(track)
    rescue Soundcloud::ResponseError, Timeout::Error, Errno::ECONNRESET => e
      puts "Soundcloud::ResponseError - #{e} #{track_id}"
    end
  end

  def tracks_by_ids track_ids
    # multi-get for tracks, a maximum of 50 track ids can be fetched at once
    track_ids.sort.uniq.each_slice(50).map do |ids|
      client.get("/tracks", {ids: ids.join(",")}).select { |t| t && is_mix?(t) }
    end.flatten
  end

  def is_mix? track
    # Given a track this function does its best to determine if it's actually
    # a music mix (instead of say a gaming podcast or interview)
    return false if track.nil? || track.empty? || !track.kind_of?(Hash)

    # it better be long enough...
    return false if track['duration'].to_i < MINIMUM_TRACK_DURATION

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
    plays = track["playback_count"].to_i
    plays = 1 if plays < 1
    plays.to_f / (elapsed ** 1.2)
  end

  def recently_popular_tracks
    puts "#{Time.now}: Requesting recently popular tracks"
    tracks_by_ids(@cache.get(recent_tracks_key) || [])
  end

  def recent_tracks_key
    "recenttracks"
  end

  def client
    Soundcloud.new(client_id: SOUNDCLOUD_ID)
  end
end
