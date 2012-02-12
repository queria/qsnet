require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'mysql'

config = YAML.load_file(File.dirname(__FILE__)+'/fetch_config.yaml')

before do
  request.env['PATH_INFO'].gsub!(/\/$/, '')
end

get '' do
  erb :index
end

get '/pings' do
  @hosts = ['nix.cz', '192.168.100.50', '192.168.102.1']
  erb :pings
end

get '/arp' do
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
  erb :status
end


