#!/usr/bin/env python
"""
# -*- coding: utf-8 -*-
#
#   Copyright (c) 2016 Cisco and/or its affiliates.
#   This software is licensed to you under the terms of the Apache License, Version 2.0
#   (the "License").
#   You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
#   The code, technical concepts, and all information contained herein, are the property of
#   Cisco Technology, Inc.and/or its affiliated entities, under various laws including copyright,
#   international treaties, patent, and/or contract.
#   Any use of the material herein must be in accordance with the terms of the License.
#   All rights not expressly granted by the License are reserved.
#   Unless required by applicable law or agreed to separately in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
#   ANY KIND, either express or implied.
#
# This script installs influx-db, telegraf , jetty and jolokia
"""

import os
import os.path
import json
import time
import logging
import yaml

import subprocess_to_log
os.chdir(os.path.dirname(os.path.abspath(__file__)))

LOG_FILE_NAME = 'logs/pnda-metrics-cli.%s.log' % time.time()
logging.basicConfig(filename=LOG_FILE_NAME,
                    level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

LOG_FORMATTER = logging.Formatter(
    fmt='%(asctime)s %(levelname)-8s %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
LOG = logging.getLogger('everything')
CONSOLE = logging.getLogger('console')
CONSOLE.addHandler(logging.StreamHandler())
CONSOLE.handlers[0].setFormatter(LOG_FORMATTER)


def write_metrics_env_sh(pnda_env):
    """
       convert Yaml file to Bash environment variable
    """
    with open('./metrics_env.sh', 'w') as pnda_env_sh_file:
        for section in pnda_env:
            for setting in pnda_env[section]:
                val = '"%s"' % pnda_env[section][setting] if isinstance(
                    pnda_env[section][setting], (list, tuple)) else pnda_env[section][setting]
                pnda_env_sh_file.write('export %s=%s\n' % (setting, val))

def write_ssh_config(bastion_ip, os_user, keyfile):
    """
       Create the ssh config file to connect bastion node
    """
    with open('ssh_config-metrics', 'w') as config_file:
        config_file.write('host *\n')
        config_file.write('    User %s\n' % os_user)
        config_file.write('    IdentityFile %s\n' % keyfile)
        config_file.write('    StrictHostKeyChecking no\n')
        config_file.write('    UserKnownHostsFile /dev/null\n')
        if bastion_ip:
            config_file.write('    ProxyCommand ssh -i %s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null %s@%s exec nc %%h %%p\n'
                              % (keyfile, os_user, bastion_ip))
    if not bastion_ip:
        return False


def ssh(cmds, bastion_ip, host, username, pem_key):
    """
       Create the ssh connection and execute the command
    """
    cmd = "ssh -i %s %s@%s" % (pem_key, username, host)
    if bastion_ip:
        cmd = "ssh -F ssh_config-metrics %s" % (host)
    parts = cmd.split(' ')
    parts.append(';'.join(cmds))
    CONSOLE.debug(json.dumps(parts))
    ret_val = subprocess_to_log.call(parts, LOG, host, scan_for_errors=[
        r'lost connection', r'\s*Failed:\s*[1-9].*'])
    if ret_val != 0:
        raise Exception("Error running ssh commands on host %s. See debug log (%s) for details." % (
            host, LOG_FILE_NAME))


def scp(files, bastion_ip, host, username, pem_key):
    """
       copy specfied files into remote node`
    """
    cmd = "scp -i %s %s %s@%s:%s" % (pem_key,
                                     ' '.join(files), username, host, '/tmp')
    if bastion_ip:
        cmd = "scp -F ssh_config-metrics %s %s:%s" % (
            ' '.join(files), host, '/tmp')
    CONSOLE.debug(cmd)
    ret_val = subprocess_to_log.call(cmd.split(' '), LOG, host)
    if ret_val != 0:
        raise Exception('''Error transferring files to new host %s via SCP.
             See debug log (%s) for details.''' % (host, LOG_FILE_NAME))


def main():
    """
       Main function
    """
    CONSOLE.info('Saving debug log to %s', LOG_FILE_NAME)
    with open('metrics_env.yaml', 'r') as infile:
        pnda_env = yaml.load(infile)

    if 'JETTY_IP' not in pnda_env['environment']:
        pnda_env['environment']['JETTY_IP'] = pnda_env['environment']['METRIC_SERVER']
    if 'INFLUXDB_IP' not in pnda_env['environment']:
        pnda_env['environment']['INFLUXDB_IP'] = pnda_env['environment']['METRIC_SERVER']
    write_metrics_env_sh(pnda_env)
    metric_server_username = pnda_env['environment']['METRIC_SERVER_USER_NAME']
    metric_server_ip = pnda_env['environment']['METRIC_SERVER']
    pem_file = pnda_env['environment']['PEM_FILE']

    bastion_ip = None
    if 'BASTION_IP' in pnda_env['environment']:
        bastion_ip = pnda_env['environment']['BASTION_IP']
        if bastion_ip:
            write_ssh_config(bastion_ip, metric_server_username, pem_file)

    files_to_scp = ['metrics_env.sh',
                    'influx/influxdb.conf', 'influx/influxdb_install.sh',
                    'jetty/jetty_install.sh', 'jetty/start.ini',
                    'telegraf/telegraf.conf_tmpl', 'telegraf/telegraf_install.sh',
                    'telegraf/telegraf_mbean.yaml']
    CONSOLE.info('''Copying supporting file to Metrics server .
                  Expect this to take a few minutes,
                  check the debug log for progress (%s).''', LOG_FILE_NAME)
    scp(files_to_scp, bastion_ip, metric_server_ip,
        metric_server_username, pem_file)

    CONSOLE.info('''Metrics package installation started. Expect this to take a few minutes,
                  check the debug log for progress (%s).''', LOG_FILE_NAME)
    cmds_to_run = ['source /tmp/metrics_env.sh',
                   'sudo chmod a+x /tmp/influxdb_install.sh',
                   'sh /tmp/influxdb_install.sh',
                   'sudo chmod a+x /tmp/jetty_install.sh',
                   'sh /tmp/jetty_install.sh',
                   'sudo chmod a+x /tmp/telegraf_install.sh',
                   'sh /tmp/telegraf_install.sh']

    ssh(cmds_to_run, bastion_ip, metric_server_ip,
        metric_server_username, pem_file)
    CONSOLE.info(''' Installation Completed''')
if __name__ == "__main__":
    try:
        main()
    except Exception as exception:
        CONSOLE.error(exception)
        raise
