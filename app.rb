require 'rubygems'
require 'bundler/setup'
require 'sinatra'

before do
  request.env['PATH_INFO'].gsub!(/\/$/, '')
end

get '' do
  erb :index
end

get '/status' do
  erb :status
end

get '/pings' do
  @hosts = ['nix.cz', '192.168.100.50', '192.168.102.1']
  erb :pings
end


