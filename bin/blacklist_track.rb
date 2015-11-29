#!/usr/bin/env ruby
require "rubygems"
require "json"
require "soundcloud"
require "yaml"

SOUNDCLOUD_ID = ENV["SOUNDCLOUD_ID"] || YAML.load_file("./config/soundcloud.yml")["id"]
BLACKLIST_PATH = "./config/blacklist.yml"

client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
track = client.get('/resolve', :url => ARGV[0])
user_id = track["user"]["id"].to_i

if user_id && user_id > 0
  blacklist = YAML.load_file(BLACKLIST_PATH)
  blacklist["blacklist"]["userid"] << user_id
  blacklist["blacklist"]["userid"].sort!.uniq!

  File.open(BLACKLIST_PATH, 'w') { |f| f.write(blacklist.to_yaml)  }
  puts "Genre: #{track['genre']}"
  puts "Tags: #{track['tag_list']}"
else
  puts "Error: userid was not valid!"
end

