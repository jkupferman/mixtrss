require './lib/track_refresher'

task :default => [:noop]

task :noop do
end

task :refresh_tracks do
  # Heroku only has hourly tasks, we only want to run ever four hours so don't actually run on the off-cycles.
  if ENV["RACK_ENV"] == "production" && Time.now.hour % 4 == 0
    print "Skipped!"
  else
    TrackRefresher.new.refresh!
  end
end
