dns-ipmonitor

This program exists to allow a freebsd (or macos) computer
to monitor dns addresses and add them to preconfigured pf
tables.

It works by either polling a pre-configured list of domains
periodically for ip addressess, or by matching regexs
against dns addressess provided by a tapper, and adding those
domains to the poll list.  The ip addressess discovered
then are added to the configured table, which can be used
in any way that pfctl is configured to use those tables.

* requirements *
In order to use the program, the dnstap module is required,
which is provided through https://github.com/raincityio/dns-dnstap.

* example config *
The following configuration operated on the "blacklist"
table of pfctl.  It adds two configured elements, a preconfigured
static domain, as well as a regex used against the tapper
to match any number of domains.

 {
     "blacklist": {
         "domains": {
             "baddomain.com"
         },
         "regexs": {
             "(.*\\.)?anotherbaddomain.com"
         }
     }
 }
