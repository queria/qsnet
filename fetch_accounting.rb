#!/usr/bin/env ruby

# vim: set et sw=2 ts=2 nowrap:

require 'rubygems'
require 'yaml'
require 'mysql'
require 'open-uri'

###
### Fetch and parse accounting data from RouterOS
###

class AccountingFetcher
  def initialize(local_matcher, enable_debug=false)
    @local_matcher = local_matcher
    @is_debug = enable_debug
  end

  def debug(msg)
    puts msg if @is_debug
  end

  def parse(row)
    row = row.split(' ')
    entry = {'src' => row[0], 'dst' => row[1],
     'bytes' => row[2], 'packets' => row[3] }
    entry['src_local'] = local? entry['src']
    entry['dst_local'] = local? entry['dst']
    return entry
  end

  def local?(ip)
    @local_matcher and @local_matcher.match(ip)
  end

  def has(host, remote=nil)
    return false if not @res.include?(host)
    return (remote.nil? or @res[host].include?(remote))
  end

  def sum(trafficA, trafficB)
    res = {}
    ['up', 'down', 'pckt_up', 'pckt_down'].each do |attr|
      res[attr] = trafficA[attr].to_i + trafficB[attr].to_i
    end
    res
  end

  def account(host, remote, traffic)
    if has(host)
      if has(host,remote)
        traffic = sum(traffic, @res[host][remote])
      end
    else
      @res[host] = {}
    end

    @res[host][remote] = traffic
  end

  def process(entry)
    if entry['src_local'] and entry['dst_local']
      debug "Skipping Local traffic #{entry['src']} => #{entry['dst']}"
      return
    end

    host = entry['src']
    remote = entry['dst']
    traffic = {'up'=>0, 'down'=>0, 'pckt_up'=>0, 'pckt_down'=>0}

    if entry['dst_local'] or has(entry['dst'])
      # swap them
      host = entry['dst']
      remote = entry['src']
      debug "#{host} <-> #{remote} download #{entry['bytes']}"
      # and count against downloaded
      traffic['down'] = entry['bytes']
      traffic['pckt_down'] = entry['packets']
    else
      # keep direction and count against uploaded
      debug "#{host} <-> #{remote} upload #{entry['bytes']}"
      traffic['up'] = entry['bytes']
      traffic['pckt_up'] = entry['packets']
    end
      
    account(host, remote, traffic)
  end

  def fetch(source_url)
    @res = {}
    open(source_url) do |src|
      while( line = src.gets )
        process(parse(line))
      end
    end
    @res
  end
end

###
### Updates data in DB
###
def sorted_ip(hosts_hash)
  hosts_hash.keys.sort_by { |ip|
    a,b,c,d = ip.split('.');
   [a.to_i, b.to_i, c.to_i, d.to_i]
  }
end

def store_accounting(db, acc_data, source_id)
  now = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z') #v novejsim ruby muzem zjednodusit na Time#iso8601
  acc_data.keys.each do |host|
    acc_data[host].keys.each do |remote|
      d = acc_data[host][remote]
      query = 'INSERT INTO accounting ' +
               '(fetched_at, host, remote, up, down, pckt_up, pckt_down, source) ' +
               "VALUES ('#{now}', '#{host}', '#{remote}', " +
               "'#{d['up']}', '#{d['down']}', " +
               "'#{d['pckt_up']}', #{d['pckt_down']}, #{source_id})"
      db.query(query)
    end
  end
end

###
### MAIN
###

if __FILE__ == $0

  config = YAML.load_file(File.dirname(__FILE__)+'/config.yaml')

  db = Mysql::new(
    config['db']['host'],
    config['db']['user'],
    config['db']['password'],
    config['db']['name'])

  #db.query('truncate accounting')

  if not config['accounting']
    puts 'No account configuration found!'
    exit 1
  end
  if not config['accounting']['sources']
    puts 'No account configuration found!'
    exit 1
  end

  local_matcher = nil
  if config['accounting']['local']
    local_matcher = Regexp.new(config['accounting']['local'])
  end
  
  acc = AccountingFetcher.new(local_matcher) #, true)

  config['accounting']['sources'].each_with_index do |acc_source, src_idx|
    store_accounting(db, acc.fetch(acc_source), src_idx + 1)
  end


  db.close

end

