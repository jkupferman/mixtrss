require './lib/track_refresher'

task :default => [:noop]

task :noop do
end

task :refresh_tracks do
  TrackRefresher.new.refresh!
end
