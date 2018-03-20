require './lib/track_refresher'

task default: [:refresh_tracks]

task :refresh_tracks do
  fast = ENV["fast"].to_s == "true"
  TrackRefresher.new.refresh! fast
end
