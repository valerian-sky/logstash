#!/bin/bash
targetEnv=$1
public_ip=

case $targetEnv in
  develop)
  export target_user=dm
  export public_ip=52.233.155.169
  export logstash_ip=10.0.0.12
  ;;
  stage)
  export target_user=dm
  export public_ip=13.81.248.126
  export logstash_ip=10.26.17.7
  ;;
  prod)
  export target_user=dm
  export public_ip=13.81.203.28
  export logstash_ip=10.26.18.6
  ;;
  *)
  echo $targetEnv | grep -P -x "(\d+\.)+(\d+)|develop|stage|prod"
  if [[ "$?" > 0 ]]; then
    echo "\$2 = $2 not supported. it must be an IPv4 address or one of develop, stage"
    exit 1
  else
    export public_ip=$2
    echo "$public_ip"
    export targetEnv=default
  fi
esac
