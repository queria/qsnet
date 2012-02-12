#!/usr/bin/env ruby

require 'yaml'
require 'mysql'



###
### Used to obtain ARP table from RouterOS via SNMP
###

def parse_table_from_snmp(snmp_arp_table)
  row_pattern = /IP-MIB::([a-zA-Z]+)\.([0-9\.]+) = [a-zA-Z]+: (.*)$/mi
  table = {}

  snmp_arp_table.split("\n").each do |snmp_row|
    row = snmp_row.match(row_pattern)
    next unless row

    table[row[2]] ||= {}
    table[row[2]][row[1]] = row[3]
  end
  return table
end

def snmp_row_to_obj(snmp_row)
    {
      'ip' => snmp_row['ipNetToMediaNetAddress'],
      'mac' => snmp_row['ipNetToMediaPhysAddress'],
      'type' => snmp_row['ipNetToMediaType']
    }
end

def transform_snmp_rows(table)
  table
  .reject { |id,arp| arp['ipNetToMediaType'] == 'invalid(2)' }
  .collect { |id,arp| snmp_row_to_obj(arp) }
end

def load_arp_from_snmp(host, community, oid)
  transform_snmp_rows(
    parse_table_from_snmp(
      `snmpwalk -v1 -c #{community} #{host} #{oid}`))
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
  now = Time.now
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

  config = YAML.load_file(File.dirname(__FILE__)+'/fetch_config.yaml')

  db = Mysql::new(
    config['db']['host'],
    config['db']['user'],
    config['db']['password'],
    config['db']['name'])

  old_entries = load_last_ip_entries(db)

  new_entries = load_arp_from_snmp(
    config['arp']['host'],
    config['arp']['community'],
    config['arp']['oid'])

  store_new_ip_entries(db, old_entries, new_entries)

  db.close

end

