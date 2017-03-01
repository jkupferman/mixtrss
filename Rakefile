require './lib/track_refresher'

task default: [:refresh_tracks]

task :refresh_tracks do
  # Heroku only has hourly tasks, we only want to run every 8 hours so don't actually run on the off-cycles.
  if (ENV["RACK_ENV"] == "production" && Time.now.hour % 8 == 0) || ENV["force"]
    fast = ENV["fast"].to_s == "true"
    TrackRefresher.new.refresh! fast
  else
    print "Skipped!"
  end
end
