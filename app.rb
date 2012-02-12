require 'rubygems'
require 'bundler/setup'
require 'sinatra'

before do
  request.env['PATH_INFO'].gsub!(/\/$/, '')
end

get '' do
  erb :index
end

get '/about' do
  erb :about
end

