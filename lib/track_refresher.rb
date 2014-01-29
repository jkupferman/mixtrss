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
  RETURN_PAGE_SIZE = 10
  MINIMUM_TRACK_DURATION = 1200000
  EXPLORE_CATEGORIES = ["Popular%2BMusic", "dubstep", "house", "electronic", "pop", "techno",
                        "rock", "reggae", "mixtape", "minimal%2Btechno", "ambient", "deep%2Bhouse",
                        "drum%2B%26%2Bbass", "electro", "hardcore%2Btechno"]

  AVAILABLE_GENRES = Common::AVAILABLE_GENRES

  def initialize
    @cache = Dalli::Client.new
  end

  def refresh!
    tracks  = tracks_from_search + tracks_from_explore + recently_popular_tracks

    tracks.uniq! { |t| t['uri'] }

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

    @cache.set(recent_tracks_key, tracks[0...500].map { |t| t['id'].to_s })
  end

  def tracks_from_search
    # scour the soundcloud search api to get all the mixes we can find. this method takes about five minutes to run
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
      client.get("/tracks", params).to_a.select { |t| t && is_mix?(t) }
    rescue Soundcloud::ResponseError, Timeout::Error, Errno::ECONNRESET, Crack::ParseError => e
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

  def tracks_from_explore
    # returns the list of track ids that are featured in soundclouds explore section
    track_ids = []
    EXPLORE_CATEGORIES.each do |category|
      # soundcloud exposes explore via their web api which isnt accessible via the gem, so grab it from the url directly
      url = "https://api-web.soundcloud.com/explore/#{category}?tag=uniform-time-decay-experiment%3A1%3A1389973574&limit=50&offset=0&linked_partitioning=1"
      begin
        json = JSON.parse(open(url).read)
      rescue OpenURI::HTTPError
        puts "Error fetching explore category #{category}"
      end
      track_ids.concat json['tracks'].map { |t| t['id'].to_s } if json
    end
    tracks_by_ids track_ids
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
    plays = track["playback_count"].to_i
    plays = 1 if plays < 1
    plays.to_f / (elapsed ** 1.2)
  end

  def recently_popular_tracks
    tracks_by_ids(@cache.get(recent_tracks_key) || [])
  end

  def recent_tracks_key
    "recenttracks"
  end

  def client
    Soundcloud.new(client_id: SOUNDCLOUD_ID)
  end
end
