#!/bin/bash
set -e

CMD="$@"

alias errecho='>&2 echo'

function write_to_logstash() {
  local ip="$( echo "$ELASTICSEARCH_IP" | sed 's/\(\/\)/\\\//g' )"
  local port="$( echo "$ELASTICSEARCH_PORT" | sed 's/\(\/\)/\\\//g' )"

  cat /etc/logstash/conf.d/logstash.ctmpl \
      | sed -e "s/#ELASTICSEARCH_URL#/${ip}:${port}/g" \
      > /etc/logstash/conf.d/logstash.conf
}

write_to_logstash

exec $CMD
