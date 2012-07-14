#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'soundcloud'

SOUNDCLOUD_CONFIG = YAML.load_file("config/soundcloud.yml")

get '/' do
  'Hello World'
end

get '/mixes' do
  client = Soundcloud.new(:client_id => SOUNDCLOUD_CONFIG["id"])

  tracks = client.get('/tracks',
                      :genres => 'mashup',
                      :duration => {
                        :from => 1200000
                      },
                      :order => 'hotness',
                      :limit => 100
                      )

  tracks.sort_by { |t| t.playback_count }.reverse.to_json
end
