#!/usr/bin/env python3.7

import sys
sys.path.append('/home/drew/dnstap/bin')

import re
import asyncio
import dns.resolver
import json
import argparse
import subprocess
import time
import os
import signal
import logging
import dnstap_client

state_file = '/var/db/ipmonitor.state'

def load_config(file):
    if os.path.lexists(file):
        with open(file, 'r') as infile:
            return json.load(infile)
    else:
        return {}

def get_ips(domain):
    try:
        return list(map(lambda r: str(r), dns.resolver.query(domain)))
    except dns.resolver.NXDOMAIN:
        return []

def pft_flush(table):
    logging.debug("pft_flush(%s)" % table)
    subprocess.run(['pfctl', '-q', '-t', table, '-T', 'flush'], check=True)

def pft_add(table, ip):
    logging.debug("pft_add(%s, %s)" % (table, ip))
    subprocess.run(['pfctl', '-q', '-t', table, '-T', 'add', ip], check=True)

def pft_remove(table, ip):
    logging.debug("pft_remove(%s, %s)" % (table, ip))
    subprocess.run(['pfctl', '-q', '-t', table, '-T', 'delete', ip], check=True)

def pft_list(table):
    output = subprocess.check_output(['pfctl', '-t', table, '-T', 'show'])
    ips = set()
    for line in output.decode('utf-8').split('\n'):
        line = line.strip()
        if len(line) > 0:
            ips.add(line)
    return ips

class JsonState:

    def __init__(self):
        self.state = self._load()

    def _load(self):
        if os.path.lexists(state_file):
            with open(state_file, 'r') as infile:
                state = json.load(infile)
        else:
            state = {}
        return state

    def save(self):
        data = json.dumps(self.state)
        with open(state_file, 'w') as outfile:
            outfile.write(data)

    def update(self, domain, update_ips):
        # update the ip list
        if not domain in self.state:
            self.state[domain] = {}
        for ip in update_ips:
            self.state[domain][ip] = time.time() + 3600

        # gather ips
        ips = []
        to_remove = []
        for (ip, ttl) in self.state[domain].items():
            if ttl > time.time():
                ips.append(ip)
            else:
                to_remove.append(ip)

        # prune expired ips
        for ip in to_remove:
            del self.state[domain][ip]

        # prune empty domain
        if len(self.state[domain]) == 0:
            del self.state[domain]

        return ips

    def remove_domain(self, domain):
        del self.state[domain]

    def get_domains(self):
        return self.state.keys()

async def main():
    state = JsonState()
    tables = []
    try:
        await _main(state, tables)
    finally:
        state.save()
        for table in tables:
            pft_flush(table)

async def _main(state, tables):
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', help='config')
    args = parser.parse_args()
    
    logging.basicConfig(level=logging.DEBUG)
    loop = asyncio.get_event_loop()
    
    finish = asyncio.Event()
    def on_signal(*args):
        finish.set()
    loop.add_signal_handler(signal.SIGINT, on_signal)
    loop.add_signal_handler(signal.SIGTERM, on_signal)
    
    reload_config = asyncio.Event()
    reload_config.set()
    def reload_signal(*args):
        reload_config.set()
    loop.add_signal_handler(signal.SIGUSR1, reload_signal)
    
    async def tapper_callback(domain, ip):
        domain = domain[:-1]
        if domain in domains:
            logging.debug("dnstap: %s = %s" % (domain, ip))
            state.update(domain, [str(ip)])
        else:
            pass

    tapper = dnstap_client.Tapper(tapper_callback)
    asyncio.create_task(tapper.loop())

    domains = {}
    domainsx = []
    while not finish.is_set():
        if reload_config.is_set():
            logging.debug("reloading config")
            config = load_config(args.c)

            new_domains = {}
            new_domainsx_tmp = {}
            new_tables = []
            for table in config:
                new_tables.append(table)
                if 'domains' in config[table]:
                    for domain in config[table]['domains']:
                        if not domain in new_domains:
                            new_domains[domain] = []
                        if not table in new_domains[domain]:
                            new_domains[domain].append(table)
                if 'domainsx' in config[table]:
                    for domainx in config[table]['domainsx']:
                        if not domainx in new_domainsx_tmp:
                            new_domainsx_tmp[domainx] = []
                        if not table in new_domainsx_tmp[domainx]:
                            new_domainsx_tmp[domainx].append(table)

            # compile regexs
            new_domainsx = []
            for kv in new_domainsx_tmp.items():
                new_domainsx.append((re.compile(kv[0]), kv[1],))
            domainsx = new_domainsx

            # flush any tables no in config
            for table in tables:
                if not table in new_tables:
                    pft_flush(table)

            tables.clear()
            tables.extend(new_tables)
            domains = new_domains

            # prune domains from state
            state_domains = state.get_domains()
            to_remove = []
            for domain in state_domains:
                if not domain in domains:
                    to_remove.append(domain)
            for domain in to_remove:
                state.remove_domain(domain)

            # config now reloaded
            reload_config.clear()

        # prime the table ips
        tables_ips = {}
        for table in tables:
            tables_ips[table] = set()

        # populate table ips
        for kv in domains.items():
            domain = kv[0]
            ips = get_ips(domain)
            state_ips = state.update(domain, ips)
            for table in kv[1]:
                table_ips = tables_ips[table]
                for ip in state_ips:
                    table_ips.add(ip)

        # remove ips from pft that no longer belong
        # also, add ips that should be there
        for table in tables:
            pft_ips = pft_list(table)
            table_ips = tables_ips[table]
            for ip in pft_ips:
                if not ip in table_ips:
                    pft_remove(table, ip)
            for ip in table_ips:
                if not ip in pft_ips:
                    pft_add(table, ip)

        # wait some time or bounce if reload
        for i in range(60):
            if reload_config.is_set():
                break
            try:
                await asyncio.wait_for(finish.wait(), 1)
                break
            except asyncio.TimeoutError:
                pass

        # meh, save the state every minute
        state.save()

if __name__ == '__main__':
    asyncio.run(main())
