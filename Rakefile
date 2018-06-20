require './lib/track_refresher'

task default: [:refresh_tracks]

task :refresh_tracks do
  # Heroku only has daily tasks, we only want to run once a week
  if (ENV["RACK_ENV"] == "production" && [1].include?(Date.today.wday)) || ENV["force"]
    fast = ENV["fast"].to_s == "true"
    TrackRefresher.new.refresh! fast
  else
    print "Skipped!"
  end
end
