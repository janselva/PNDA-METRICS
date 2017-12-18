import uuid
import sys
import os
import os.path
import json
import time
import logging
import atexit
import traceback
import datetime
import tarfile
import ssl
import Queue

from threading import Thread

import requests
import boto.cloudformation
import boto.ec2
import yaml

import subprocess_to_log
os.chdir(os.path.dirname(os.path.abspath(__file__)))

LOG_FILE_NAME = 'logs/pnda-metrics-cli.%s.log' % time.time()
logging.basicConfig(filename=LOG_FILE_NAME,
                    level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

LOG_FORMATTER = logging.Formatter(fmt='%(asctime)s %(levelname)-8s %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
LOG = logging.getLogger('everything')
CONSOLE = logging.getLogger('console')
CONSOLE.addHandler(logging.StreamHandler())
CONSOLE.handlers[0].setFormatter(LOG_FORMATTER)

def write_metrics_env_sh():
  with open('./metrics_env.sh', 'w') as pnda_env_sh_file:
    for section in PNDA_ENV:
      for setting in PNDA_ENV[section]:
        val = '"%s"' % PNDA_ENV[section][setting] if isinstance(PNDA_ENV[section][setting], (list, tuple)) else PNDA_ENV[section][setting]
        pnda_env_sh_file.write('export %s=%s\n' % (setting, val))
  

def write_ssh_config(bastion_ip, os_user, keyfile):
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

def ssh(cmds, bastion_ip,host,username,pem_key):
    cmd = "ssh -i %s %s@%s" % (pem_key,username, host)
    if bastion_ip:
       cmd = "ssh -F ssh_config-metrics %s" % ( host)
    parts = cmd.split(' ')
    parts.append(';'.join(cmds))
    CONSOLE.debug(json.dumps(parts))
    ret_val = subprocess_to_log.call(parts, LOG, host, scan_for_errors=[r'lost connection', r'\s*Failed:\s*[1-9].*'])
    if ret_val != 0:
        raise Exception("Error running ssh commands on host %s. See debug log (%s) for details." % (host, LOG_FILE_NAME))
def scp(files,bastion_ip,  host, username, pem_key):
    cmd = "scp -i %s %s %s@%s:%s" % (pem_key, ' '.join(files), username, host, '/tmp')
    if bastion_ip:
        cmd = "scp -F ssh_config-metrics %s %s:%s" % ( ' '.join(files), host, '/tmp')
    CONSOLE.debug(cmd)
    ret_val = subprocess_to_log.call(cmd.split(' '), LOG, host)
    if ret_val != 0:
        raise Exception("Error transferring files to new host %s via SCP. See debug log (%s) for details." % (host, LOG_FILE_NAME))

		

def main():
  CONSOLE.info('Saving debug log to %s' % LOG_FILE_NAME)

  global PNDA_ENV
  with open('metrics_env.yaml', 'r') as infile:
    PNDA_ENV = yaml.load(infile)

  if 'JETTY_IP' not in PNDA_ENV['environment'] :
     PNDA_ENV['environment']['JETTY_IP'] = PNDA_ENV['environment']['METRIC_SERVER_IP']
  if 'INFLUXDB_IP' not in PNDA_ENV['environment'] :
     PNDA_ENV['environment']['INFLUXDB_IP'] = PNDA_ENV['environment']['METRIC_SERVER_IP']
  write_metrics_env_sh()
  metric_server_username = PNDA_ENV['environment']['METRIC_SERVER_USER_NAME']
  metric_server_ip = PNDA_ENV['environment']['METRIC_SERVER_IP']
  pem_file = PNDA_ENV['environment']['PEM_FILE']



  bastion_ip = None
  if 'BASTION_IP' in PNDA_ENV['environment']:
      bastion_ip = PNDA_ENV['environment']['BASTION_IP']
      if bastion_ip:
         write_ssh_config(bastion_ip, metric_server_username, pem_file)

  files_to_scp = [  'metrics_env.sh',
                    'influx/influxdb.conf','influx/influxdb_install.sh',
                    'jetty/jetty_install.sh','jetty/start.ini',
                    'telegraf/telegraf.conf_tmp','telegraf/telegraf_install.sh','telegraf/telegraf.service']

  CONSOLE.info('Copying supporting file to Metrics server . Expect this to take a few minutes, check the debug log for progress (%s).', LOG_FILE_NAME)
  scp(files_to_scp,bastion_ip,metric_server_ip,metric_server_username,pem_file)



  CONSOLE.info('Metrics package installation started. Expect this to take a few minutes, check the debug log for progress (%s).', LOG_FILE_NAME)
  cmds_to_run = ['source /tmp/metrics_env.sh',
               'sudo chmod a+x /tmp/influxdb_install.sh',
               'sh /tmp/influxdb_install.sh',
               'sudo chmod a+x /tmp/jetty_install.sh',
               'sh /tmp/jetty_install.sh',
               'sudo chmod a+x /tmp/telegraf_install.sh',
               'sh /tmp/telegraf_install.sh']

  ssh(cmds_to_run,bastion_ip,metric_server_ip, metric_server_username,pem_file)





if __name__ == "__main__":
    try:
        main()
    except Exception as exception:
        CONSOLE.error(exception)
        raise
