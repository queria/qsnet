#!/usr/bin/env python
import os
import pexpect
import sys

# Usage:
#  ./ping-via-mtik.py [-cCOUNT:1] <DST> <VIA_MIKROTIK> [USER:ping] [SSH_KEY:~/.ssh/id_dsa]
#
# ex.
#  ./ping-via-mtik.py -c3 example.org 10.0.0.254 monitor ~/.ssh/monitor_key

print('MTikPing ...')
args = [opt for opt in sys.argv[1:] if not opt.startswith('-c')]
counts = [int(opt[2:]) for opt in sys.argv if opt.startswith('-c')]


target = args[0]
mtik = args[1]
user = 'ping'
key = '~/.ssh/id_dsa'
count = 1
if len(args) > 2:
    user = args[2]
if len(args) > 3:
    key = args[3]
if len(counts):
    count = counts[-1]

key = os.path.expanduser(key)

p = pexpect.spawn("ssh -l %s -i %s %s"
    % (user, key, mtik))
#print(p)
p.expect('\[%s@[^\]]+\] >' % user)
p.logfile = sys.stdout
p.send("/ ping %s count=%d\r" % (target, count))
#p.expect('/ ping')
p.expect('[0-9a-zA-Z,\ ]+ [0-9]+% packet loss')
#p.expect('packet loss')
#p.expect('\[ping@HaskyTik\] >')

#print(p.before)
#print('--')
#print(p.after)

print('')
