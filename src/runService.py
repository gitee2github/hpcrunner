#!/usr/bin/env python3
# -*- coding: utf-8 -*- 
import os
import sys
from toolService import ToolService
from executeService import ExecuteService
from dataService import DataService

class RunService:
    def __init__(self):
        self.hpc_data = DataService()
        self.exe = ExecuteService()
        self.tool = ToolService()
        self.ROOT = os.getcwd()
        self.avail_ips_list = self.tool.gen_list(DataService.avail_ips)

    def gen_hostfile(self, nodes):
        length = len(self.avail_ips_list)
        if nodes > length:
            print(f"You don't have {nodes} nodes, only {length} nodes available!")
            sys.exit()
        if nodes <= 1:
            return
        gen_nodes = '\n'.join(self.avail_ips_list[:nodes])
        print(f"HOSTFILE\n{gen_nodes}\nGENERATED.")
        self.tool.write_file('hostfile', gen_nodes)

    # single run
    def run(self):
        print(f"start run {DataService.app_name}")
        nodes = int(DataService.run_cmd['nodes'])
        self.gen_hostfile(nodes)
        run_cmd = self.hpc_data.get_run_cmd()
        self.exe.exec_raw(run_cmd)

    def batch_run(self):
        batch_file = 'batch_run.sh'
        batch_file_path = os.path.join(self.ROOT, batch_file)
        print(f"start batch run {DataService.app_name}")
        batch_content = f'''
cd {DataService.case_dir}
{DataService.batch_cmd}
'''
        self.tool.write_file(batch_file_path, batch_content)
        run_cmd = f'''
chmod +x {batch_file}
./{batch_file}
'''
        self.exe.exec_raw(run_cmd)