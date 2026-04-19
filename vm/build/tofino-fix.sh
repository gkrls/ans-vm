#!/bin/bash
# Usage:
#   bash fix.sh          # Add taskset
#   bash fix.sh remove   # Remove taskset

FILE=~/p4-tools/p4-utils/p4utils/mininetlib/node.py

# Always remove first
sed -i "s|args = \['taskset', '-c', str(int(self.name\[1:\]) % os.cpu_count()), os.path.join(self.sde, 'run_tofino_model.sh')\]|args = [os.path.join(self.sde, 'run_tofino_model.sh')]|" $FILE
sed -i "s|args = \['taskset', '-c', str(int(self.name\[1:\]) % os.cpu_count()), os.path.join(self.sde, 'run_switchd.sh')\]|args = [os.path.join(self.sde, 'run_switchd.sh')]|" $FILE

if [ "$1" != "remove" ]; then
    sed -i "s|args = \[os.path.join(self.sde, 'run_tofino_model.sh')\]|args = ['taskset', '-c', str(int(self.name[1:]) % os.cpu_count()), os.path.join(self.sde, 'run_tofino_model.sh')]|" $FILE
    sed -i "s|args = \[os.path.join(self.sde, 'run_switchd.sh')\]|args = ['taskset', '-c', str(int(self.name[1:]) % os.cpu_count()), os.path.join(self.sde, 'run_switchd.sh')]|" $FILE
    echo "Taskset ADDED:"
else
    echo "Taskset REMOVED:"
fi

grep -n "run_tofino_model\|run_switchd" $FILE | head -4