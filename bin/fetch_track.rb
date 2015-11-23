#!/usr/bin/env ruby
require "rubygems"
require "json"
require "soundcloud"
require "yaml"

SOUNDCLOUD_ID = ENV["SOUNDCLOUD_ID"] || YAML.load_file("./config/soundcloud.yml")["id"]

client = Soundcloud.new(:client_id => SOUNDCLOUD_ID)
track = client.get('/resolve', :url => ARGV[0])
puts JSON.pretty_generate(track)
puts track["user"]["id"]
