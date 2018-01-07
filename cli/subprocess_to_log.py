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
"""
import subprocess
import select
import re
from logging import INFO


def call(cmd_to_run, logger, log_id=None, scan_for_errors=None, **kwargs):
    """
       execute the command in remote node using sub process
    """
    stdout_log_level = INFO
    stderr_log_level = INFO
    if scan_for_errors is None:
        scan_for_errors = []

    child_process = subprocess.Popen(
        cmd_to_run, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)

    log_level = {child_process.stdout: stdout_log_level,
                 child_process.stderr: stderr_log_level}

    def fetch_child_output():
        """
           fetch child process output
        """
        child_output_streams = select.select(
            [child_process.stdout, child_process.stderr], [], [], 1000)[0]
        for child_output_stream in child_output_streams:
            line = child_output_stream.readline()
            msg = line[:-1]
            msg = msg.decode('utf-8')
            if log_id is not None:
                msg_with_id = '%s %s' % (log_id, msg)
            logger.log(log_level[child_output_stream], msg_with_id)
            for pattern in scan_for_errors:
                if re.match(pattern, msg):
                    raise Exception(msg_with_id)

    while child_process.poll() is None:
        fetch_child_output()

    fetch_child_output()

    return child_process.wait()
