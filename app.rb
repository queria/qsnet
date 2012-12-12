# vim: set et sw=2 ts=2 nowrap:

require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/session'
require 'mysql'
require 'md5'
require 'yaml'


def dbconn
  if @@db.nil?
    @@db = Mysql::new(
      @@config['db']['host'],
      @@config['db']['user'],
      @@config['db']['password'],
      @@config['db']['name'])
    @@db.reconnect = true
  end
  return @@db
end

def known
  if @@known['read_at'] < (Time.now.to_i - @@config['cachetime'])
    db = dbconn
    db.query('SELECT * FROM arp_current').each_hash do |host|
      @@known['ip'][ host['ip'] ] = host
      @@known['mac'][ host['mac'] ] = host
    end
    @@known['read_at'] = Time.now.to_i
  end
  @@known
end


configure do
  @@config = YAML.load_file(File.dirname(__FILE__)+'/config.yaml')
  @@config['cachetime'] ||= (12 * 60 * 60) # 12hours
  @@config['traffic_interval'] ||= 7 # in days
  @@known = { 'ip'=>{}, 'mac'=>{}, 'read_at' => 0 }
  @@db = nil
  set :session_name, 'qsnet'
  set :session_secret, '309fjsdo 0bfnsd09 4 dsfdgd'
  set :session_expire, 600
  set :session_fail, @@config['base']['url']+'login'
  known() # initialize known ip/mac list
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

  if @login == @@config['auth']['login'] and @pass == @@config['auth']['pass']
    session_start!
    if session[:backurl]
      backurl = session[:backurl]
      session[:backurl] = nil
      redirect to(backurl)
    else
      redirect to('')
    end
  else
    redirect to("/login?login=#{@login}")
  end
end


get '/logout' do
  session_end!
  redirect to('login')
end

get '' do
  check_auth(request)
  erb :index
end

get '/pings' do
  check_auth(request)
  @hosts = @@config['ping_hosts']
  erb :pings
end

get '/arp' do
  check_auth(request)
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

  known()['mac'].each_pair do |mac,info|
    @mac_notes[ mac ] = info['note'] if info['note']
  end

  @notefor = nil
  unless params[:notefor].nil? or @mac_notes[params[:notefor]].nil?
    @notefor = params[:notefor]
  end
  @shownoteform = ( @notefor or (params[:notefor] == 'new') )

  erb :arp
end

get '/arp/delete/:id' do
  check_auth(request)
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
  check_auth(request)
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
    @@known['read_at'] = 0 # force reload of known ip/mac/note cache
  end
  redirect to('arp')
end

get '/traffic' do
  check_auth(request)
  db = dbconn

  @days = @@config['traffic_interval']
  @days = [params['days'].to_i, 1].max if params['days']
  params['days'] = @days


  if ['up', 'down', 'pckt_up', 'pckt_down'].include? params['sort']
    sort = "SUM(#{params[:sort]}) DESC"
  elsif params['sort'] == 'remotes'
    sort = "remotes DESC"
  else
    params['sort'] = 'host'
    sort = "INET_ATON(host)"
  end
  
  interval_start = (Time.now - (@days * 24 * 60 * 60))
  interval_start = interval_start.strftime('%Y-%m-%dT%H:%M:%S%z')
  @traffic = db.query("SELECT host, SUM(up) AS up, SUM(down) AS down," +
    " SUM(pckt_up) AS pckt_up, SUM(pckt_down) AS pckt_down, COUNT(remote) AS remotes" +
    " FROM accounting" +
    " WHERE fetched_at > '#{interval_start}'" +
    " GROUP BY host" +
    " ORDER BY #{sort}")

  @names = {}
  known()['ip'].each_pair do |ip,info|
    @names[ip] = info['note'] if info['note']
  end

  @sum = {'down'=>0, 'up'=>0, 'pckt_down'=>0, 'pckt_up'=>0, 'remotes'=>0} # remotes are not globaly unique!
  @traffic.each_hash { |info| @sum.keys.each { |key| @sum[key] += info[key].to_i } } #@sum.keys.each { |key| @sum[key] += info[key] } }
  @traffic.data_seek 0

  G1 = (1024 * 1024 * 1024)
  @stats = {
    'pckt_size_down' => @sum['down'] / @sum['pckt_down'],
    'pckt_size_up' => @sum['up'] / @sum['pckt_down'],
    'pckt_cnt_down' => @sum['pckt_down'] / @traffic.num_rows,
    'pckt_cnt_up' => @sum['pckt_up'] / @traffic.num_rows,
    'pckt_cnt_1g_down' => G1 / (@sum['down'] / @sum['pckt_down']),
    'pckt_cnt_1g_up' => G1 / (@sum['up'] / @sum['pckt_up']),
    #'remotes' => @traffic.methods.sort.join(', ')
    'remotes' => @sum['remotes'] / @traffic.num_rows,
    'remotes_1g_down' => G1 / (@sum['down'] / @sum['remotes']),
    'remotes_1g_up' => G1 / (@sum['up'] / @sum['remotes'])
  }
  @params = params
  erb :traffic
end

get '/status' do
  check_auth(request)
  erb :status
end

helpers do
  def check_auth(request)
    return if session?
    session[:backurl] = request.path_info
    session!
  end

  def formatBytes(bytes)
    bytes = bytes.to_f
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    idx = 0
    while bytes > 1024
      bytes = bytes / 1024
      idx += 1
    end
    suff = units[idx] or '??'
    bytes = (bytes * 100).round().to_f / 100 # just round(2) in ruby 1.9.3
    "#{bytes} #{suff}"
  end

  def formatPcktCnt(number)
    number = number.to_f
    return number.to_s if number < 1000
    number /= 1000
    return sprintf("%.2fk", number) if number < 1000
    return sprintf("%.2fmil", number/1000)
  end
  
  def sortL(text, params, key=nil)
    key = text.downcase unless key
    if key == params['sort']
      return text
    end
    params = params.clone
    params['sort'] = key
    #return "<i>#{key}</i>"
    url_params = paramsUrl(params)
    return "<a href=\"?#{url_params}\">#{text}</a>"
  end

  def paramsUrl(params)
    u = []
    params.keys.each { |k|
      kurl = k.to_s.sub(':','')
      u << "#{kurl}=#{params[k]}"
    }
    return u.join("&amp;")
  end
end

