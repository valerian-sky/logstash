#from base logstash

FROM logstash:5

# ELASTICSEARCH_IP Argument for elastic search
ARG ELASTICSEARCH_IP

#ENV setup
ENV ELASTICSEARCH_IP $ELASTICSEARCH_IP
ENV ELASTICSEARCH_PORT 9200

#COPY confi template and elasticsearch template
COPY ./config /etc/logstash/conf.d
COPY ./es-template /etc/logstash

#COPY entrypoint script
COPY entrypoint.sh /entrypoint.sh

#change mode
RUN chmod +x /entrypoint.sh

#Install prune
RUN logstash-plugin install logstash-filter-prune

#Command to execute
CMD /entrypoint.sh logstash --http.host 0.0.0.0 -f /etc/logstash/conf.d/logstash.conf

EXPOSE 5000/udp 12201/udp 9600
