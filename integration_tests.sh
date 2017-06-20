!/usr/bin/env bash

echo "usage \$1 = username, \$2 = public_ip, \$3 = service name"
echo e.g "dm 12.12.12.12 onboarding"
username=$1
public_ip=$2
serviceName=$3

check_consul_status='monitor_consul() {
for attempt in {1..5} ; do
  consulOutput=$(curl consul:8500/v1/health/service/'$serviceName' | jq -e ".[].Checks|.[]|select(.ServiceName == \"'$serviceName'\" and .Status == \"passing\")")
  if [[ "$?" > 0 ]]; then
    echo "not passing yet, current result is $consulOutput"
    sleep 5
    continue
  else
    echo "consul health passing"
    return 0
  fi
done
  echo "Consul health not passing, failing build"
  return 1
}
monitor_consul
'
echo "going to run via ssh: $check_consul_status"
echo "$check_consul_status" | ssh $username@$public_ip -p 2200 -o "StrictHostKeyChecking no"

