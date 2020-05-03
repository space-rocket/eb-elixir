#!/bin/bash
# Docker entrypoint script.

# Wait until Postgres is ready
while ! pg_isready -q -h "aa1tzxywb7y3qa4.c0p776z9fkhq.us-west-2.rds.amazonaws.com" -p 5432 -U "ebroot"
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

./bin/my_app eval "MyApp.Release.migrate" && \
./bin/my_app start