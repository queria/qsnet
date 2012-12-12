#!/usr/bin/env ruby

# vim: set et sw=2 ts=2 nowrap:

require 'rubygems'
require 'yaml'
require 'mysql'

def clear_mac(mac, delimiter=':')
  mac.gsub('-', ' ').gsub(':',' ').split(' ').collect{ |touple|
    touple.downcase.rjust(2, '0')
  }.join(delimiter)
end

def prepare_snmp_row_pattern

  # two same examples of snmp row for arp table entry
  # .1.3.6.1.2.1.4.22.1.3.13.192.168.0.1 = IpAddress: 192.168.0.1
  # IP-MIB::ipNetToMediaNetAddress.13.192.168.0.1 = IpAddress: 192.168.0.1
  
  oidprefix = ".1.3.6.1.2.1.4.22.1."
  attr = '[0-9]+'
  id = '[0-9\.]+'
  datatype = '[a-zA-Z-]+'
  value = '.*'

  return /#{Regexp.quote(oidprefix)}(#{attr})\.(#{id}) = #{datatype}: (#{value})/

end

def parse_table_from_snmp(snmp_arp_table)
  row_pattern = prepare_snmp_row_pattern
  attr_types = [nil, 'ifc', 'mac', 'ip', 'status']
  table = {}

  snmp_arp_table.split("\n").each do |snmp_row|
    row = snmp_row.match(row_pattern)
    next unless row

    table[ row[2] ] ||= {}
    table[ row[2] ][ attr_types[row[1].to_i] ] = row[3]
  end

  return table
end

def snmp_row_to_obj(snmp_row)
  snmp_row['mac'] = clear_mac(snmp_row['mac'])
  snmp_row
end

def transform_snmp_rows(table)
  table \
  .reject { |id,arp| arp['status'] == '2' } \
  .collect { |id,arp| snmp_row_to_obj(arp) }
  # status 2 == invalid
end

def load_arp_from_snmp(host, community, oid)
  transform_snmp_rows(
    parse_table_from_snmp(
      `snmpwalk -One -v1 -c #{community} #{host} #{oid}`))
end



###
### Used to update entries in database
###

def db_row_to_obj(db_row)
  db_row
end

def load_last_ip_entries(db)
  query = "SELECT id, ip, mac, seen_at " +
    " FROM arp " +
    " WHERE seen_at = " +
    " ( SELECT MAX(seen_at) FROM arp AS arp_max WHERE arp.ip = arp_max.ip )"
  entries = {}
  db.query(query).each_hash do |entry|
    entries[entry['ip']] = db_row_to_obj(entry)
  end
  entries
end

def store_new_ip_entries(db, last, new)
  now = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z') #v novejsim ruby muzem zjednodusit na Time#iso8601
  new.each do |entry|
    ip = entry['ip']
    if last[ip].nil? or last[ip]['mac'] != entry['mac']
      query = 'INSERT INTO arp ' +
               '(ip, mac, seen_at) '+
               'VALUES '+
               "('#{entry['ip']}', '#{entry['mac']}', '#{now}')"
    else
      query = "UPDATE arp " +
        "SET seen_at = '#{now}' " +
        "WHERE id = #{last[ip]['id']}"
    end
    puts query
    db.query(query)
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

  old_entries = load_last_ip_entries(db)

  unless config['arp'].is_a? Array
    config['arp'] = [ config['arp'] ]
  end

  config['arp'].each do |arp_source|
    new_entries = load_arp_from_snmp(
      arp_source['host'],
      arp_source['community'],
      arp_source['oid'])
    store_new_ip_entries(db, old_entries, new_entries)
  end


  db.close

end

