#!/bin/bash

check_database_connection() {
    local db_url=$1
    local retries=5
    local wait_time=5

    # Extract connection details from DATABASE_URL
    if [[ $db_url =~ postgres:\/\/([^:]+):([^@]+)@([^\/]+)\/(.+) ]]; then
        DB_USER="${BASH_REMATCH[1]}"
        DB_PASS="${BASH_REMATCH[2]}"
        DB_HOST="${BASH_REMATCH[3]}"
        DB_PORT="5432"  # Default PostgreSQL port
        DB_NAME="${BASH_REMATCH[4]}"
        
        echo "Found database connection details:"
        echo "Host: $DB_HOST"
        echo "Database: $DB_NAME"
        echo "User: $DB_USER"
    else
        echo "Failed to parse DATABASE_URL: $db_url"
        return 1
    fi

    echo "Checking database connection..."
    
    for i in $(seq 1 $retries); do
        if PGPASSWORD=$DB_PASS psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' > /dev/null 2>&1; then
            echo "Database connection successful!"
            return 0
        else
            echo "Attempt $i/$retries: Cannot connect to database. Waiting ${wait_time}s..."
            sleep $wait_time
        fi
    done

    echo "Failed to connect to database after $retries attempts"
    return 1
}