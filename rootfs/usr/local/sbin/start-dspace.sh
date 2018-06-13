#!/usr/bin/env bash

# Start the cron service for DSpace's scheduled maintenance tasks
# See: /etc/cron.d/dspace-maintenance-tasks
service cron start

POSTGRES_DB_HOST=${POSTGRES_DB_HOST:-$POSTGRES_PORT_5432_TCP_ADDR}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-$POSTGRES_PORT_5432_TCP_PORT}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-5432}

# Create PostgreSQL user and database schema
if [ -n $POSTGRES_DB_HOST -a -n $POSTGRES_DB_PORT ]; then
    # Wait for PostgreSQL and then call `setup-postgres.sh` script
    # See: https://docs.docker.com/compose/startup-order/
    wait-for-postgres.sh $POSTGRES_DB_HOST setup-postgres.sh
fi

#if staistics/data was mounted as a volume, then change permissions to dspace:dspace user and group
if [ -d "/dspace/solr/statistics/data" ]; then
    echo "Changing user permissions user over /dspace/solr/statistics/data directory..."
    chown -R dspace:dspace "/dspace/solr/statistics/data"
fi

exec su - dspace -c "$CATALINA_HOME/bin/catalina.sh run"
