# Centralized Logging


We have a centralized logging system powered by ELK stack

## Ports

1. Kibana - 5601
2. Logstash - 5000, 12201
3. Elasticsearch - 9200


## Kibana

A visualization tool used for querying and visualizing log data. Visiting hostname:5601 will provide a nice interface to work with log data.

## Logstash

Logstash is used as a log broker to communicate the data to elastic search from docker

### Log Drivers

### gelf :
Used for docker logs, whatever information logged into the docker container will be communicated to logstash via port 12201. Have to enable the log driver before starting the container. Refer [gelf driver](https://docs.docker.com/engine/admin/logging/overview/#gelf)

### UDP :
Listening on port 5000, mainly used by api gateway, uses UDP plugin by kong. Refer [UDP plugin](https://getkong.org/plugins/udp-log/)

## Elasticsearch

Elastic search is used as a data store for the logs, below are the details about ElasticSearch schema

### Index name

bnp_logs

### Document types

#### service :
All the logs from application (simply docker) will be logged into type service

#### gateway :
Logs from gateway will be logged to this particular type

#### Log format :

The logs from application needs to follow the following structure as JSON
```
{
    correlationId: req.headers.correlation-id [from request header],
    userId: req.headers.userData.email || req.header.userData.userId,
    serviceName: STRING (Unique per service),
    serviceInstanceId: STRING || NUMBER (Unique per service),
    message: STRING (message to be logged),
    level: ENUM ['error', 'info', 'warn', 'debug']
}
```

#### NOTE :

##### Mandatory fields

1. CorrelationId
2. message
3. level

***serviceName*** and ***serviceInstanceId*** will be supplied from headers in future, with proper keys, Hence for now supply the information as below for now.

E.g: For BNP
```
 serviceName: req.headers.x-serviceName || 'BNP'
 serviceInstanceId: req.headers.x-serviceInstanceId || 'BNP'
```

##### Docker Compose
1. To add [ELK stack](https://github.com/OpusCapitaBusinessNetwork/bnp/blob/master/docker-compose.yml#L108-L138) in docker-compose file

2. To setup [log driver](https://github.com/OpusCapitaBusinessNetwork/bnp/blob/master/docker-compose.yml#L17-L20) in docker-compose file, right now it is been set only for BNP container/app

#### ENVIRONMENT VARIABLES

------
ElasticSearch related
-----

**Description :** IP for the elastic search instance

>**ELASTICSEARCH_IP**

>>***Example value :*** 172.17.0.1

>>***Description :*** Ip address of the elastic search instance

# Deployment

## Development (Swarm)
* Register service on any swarm manager
```
docker service create --name logstash --env SERVICE_9600_NAME=logstash --env SERVICE_12201_NAME=logstash-gelf --env SERVICE_9600_CHECK_HTTP=/ --env SERVICE_9600_CHECK_INTERVAL=15s --env SERVICE_9600_CHECK_TIMEOUT=3s --env SERVICE_5000_NAME=logstash-udp --env ELASTICSEARCH_IP=elastic.service.consul --publish mode=host,target=9600,protocol=tcp,published=9600 --publish mode=host,target=5000,protocol=tcp,published=5000 --publish mode=host,target=5000,protocol=udp,published=5000 --publish mode=host,target=12201,protocol=udp,published=12201 --constraint "node.role == worker" ocbesbn/logstash:dev
```

Note: logstash is not logging to itself. This would be possible via the internal UDP loadbalancer but in case it doesn't come up
obviously wouldnt allow access to logs in order to figure what is wrong.
