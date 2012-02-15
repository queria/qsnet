require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/session'
require 'mysql'
require 'yaml'

config = YAML.load_file(File.dirname(__FILE__)+'/config.yaml')


configure do
  set :session_name, 'qsnet'
  set :session_expire, 600
end

before do
  request.env['PATH_INFO'].gsub!(/\/$/, '')
end


get '/login' do
  @login = params[:login]
  erb :login
end

post '/login' do
  @login = params[:login]
  @pass = params[:pass]

  if @login == config['auth']['login'] and @pass == config['auth']['pass']
    session_start!
    redirect to('')
  else
    redirect to("/login?login=#{@login}")
  end
end


get '/logout' do
  session_end!
  redirect to('login')
end

get '' do
  session!
  erb :index
end

get '/pings' do
  session!
  @hosts = ['nix.cz', '192.168.100.50', '192.168.102.1']
  erb :pings
end

get '/arp' do
  session!
  db = Mysql::new(
    config['db']['host'],
    config['db']['user'],
    config['db']['password'],
    config['db']['name'])

  @arp_table = {}
  ip_addresses = db.query("SELECT ip FROM arp GROUP BY ip ORDER BY ip")
  ip_addresses.each do |ip|
    ip = ip[0]
    @arp_table[ip] = []
    macs = db.query("SELECT mac, seen_at " +
                    "FROM arp WHERE ip = '#{ip}' " +
                    "ORDER BY seen_at DESC " +
                    "LIMIT 5")
    macs.each_hash do |mac|
      @arp_table[ip] << mac
    end
  end

  erb :arp
end

get '/status' do
  session!
  erb :status
end


