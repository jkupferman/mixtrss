require './lib/track_refresher'

task default: [:refresh_tracks]

task :refresh_tracks do
  # Heroku only has hourly tasks, we only want to run ever four hours so don't actually run on the off-cycles.
  if (ENV["RACK_ENV"] == "production" && Time.now.hour % 4 == 0) || ENV["force"]
    TrackRefresher.new.refresh!
  else
    print "Skipped!"
  end
end
