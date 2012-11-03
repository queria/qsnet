CREATE OR REPLACE VIEW arp_current AS
 SELECT arp.*, mn.note
 FROM arp
  LEFT JOIN mac_notes AS mn
  ON arp.mac = mn.mac
 WHERE arp.id IN (
  select max(id) from arp group by ip
 );

