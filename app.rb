require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/session'
require 'mysql'
require 'md5'
require 'yaml'

config = YAML.load_file(File.dirname(__FILE__)+'/config.yaml')


configure do
  set :session_name, 'qsnet'
  set :session_expire, 600
  set :session_fail, config['base']['url']+'login'
end

before do
  request.env['PATH_INFO'].gsub!(/\/$/, '')
  @config = config
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
  db = dbconn

  @arp_table = {}
  @mac_notes = {}
  @deleted = params[:deleted]

  ip_addresses = db.query("SELECT ip FROM arp GROUP BY ip ORDER BY ip")
  ip_addresses.each do |ip|
    ip = ip[0]
    @arp_table[ip] = []
    macs = db.query("SELECT id, mac, seen_at " +
                    "FROM arp WHERE ip = '#{ip}' " +
                    "ORDER BY seen_at DESC " +
                    "LIMIT 5")
    macs.each_hash do |mac|
      @arp_table[ip] << mac
    end
  end

  db.query("SELECT * FROM mac_notes ORDER BY note").each do |note|
    @mac_notes[note[0]] = note[1]
  end

  @notefor = nil
  unless params[:notefor].nil? or @mac_notes[params[:notefor]].nil?
    @notefor = params[:notefor]
  end
  @shownoteform = ( @notefor or (params[:notefor] == 'new') )

  erb :arp
end

get '/arp/delete/:id' do
  session!
  db = dbconn

  id = params[:id].to_i
  unless id
    redirect to('arp?deleted=invalid')
  end

  query = "DELETE FROM arp WHERE id = #{id}"
  db.query(query)
  redirect to("arp?deleted=#{db.affected_rows}")
end

post '/arp/mac_note' do
  session!
  mac = params[:mac].strip
  note = params[:note].strip

  unless mac.empty?
    db = dbconn
    existing = db.query("SELECT * FROM mac_notes WHERE mac = '#{mac}'")
    if existing.num_rows == 1
      if note.empty?
        query = "DELETE FROM mac_notes WHERE mac = '#{mac}'"
      else
        query = "UPDATE mac_notes SET note = '#{note}' WHERE mac = '#{mac}'"
      end
    else
      query = "INSERT INTO mac_notes (mac, note) VALUES ('#{mac}', '#{note}')"
    end
    db.query(query)
  end
  redirect to('arp')
end

get '/status' do
  session!
  erb :status
end

def dbconn
  if @db.nil?
    @db = Mysql::new(
      @config['db']['host'],
      @config['db']['user'],
      @config['db']['password'],
      @config['db']['name'])
  end
  return @db
end

