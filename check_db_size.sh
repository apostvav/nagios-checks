#!/bin/bash

# This script querys a MySQL server
# for the size of a specific database

# Default values
WARNING=0
CRITICAL=0

# Usage function
usage(){
  echo "Usage: $0 -H DBHOST -u DBUSER -p DBPASS -d DBNAME -w WARNING -c CRITICAL"
}

# Validate FQDN
check_fqdn() {
  local domain=`echo $1 | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'`
  if [[ -z $domain ]]; then
    echo 0
  else
    echo 1
  fi
}

# Validate IP address
check_ip() {
  local re='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}'
  re+='0*(1?[0-9]{1,2}|2([<200c><200b>0-4][0-9]|5[0-5]))$'
  if [[ $1 =~ $re ]]; then
   echo 1
  else
    echo 0
  fi
}

# Parse arguments
while getopts ":H:u:p:d:w:c:h" opt; do
  case $opt in
    H) # database hostname
      DBHOST=$OPTARG
      ;;
    u) # database username
      DBUSER=$OPTARG
      ;;
    p) # database password
      DBPASS=$OPTARG
      ;;
    d) # database name
      DBNAME=$OPTARG
      ;;
    w) # warning threshold
      WARNING=$OPTARG
      ;;
    c) # critical threshold
      CRITICAL=$OPTARG
      ;;
    h) # help
      usage
      exit 0
      ;;
    \?)
      echo "ERROR: Invalid option: -$OPTARG"
      usage
      exit 2
      ;;
    :)
      echo "ERROR: Option -$OPTARG requires an argument."
      exit 2
      ;;
  esac
done

shift $(($OPTIND - 1))

if [ ! "$DBHOST" ] || [ ! "$DBUSER" ] || [ ! "$DBPASS" ] || [ ! "$DBNAME" ]
then
    echo "UNKNOWN: Mandatory options are missing"
    exit 3
fi

# Validate host
isFQDN=$(check_fqdn $DBHOST)
isIPADDR=$(check_ip $DBHOST)
if [ "$isFQDN" != 1 ] && [ "$isIPADDR" != 1 ]; then
    echo "UNKNOWN: Not a valid DB Host"
    exit 3
fi

# Query MySQL server
SQLQUERY="SELECT SUM(ROUND(((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024 ), 0)) AS 'SIZE IN MB'
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$DBNAME';"
DBSIZE=$(mysql --host=$DBHOST --user=$DBUSER --password="$DBPASS" -s -N -e "$SQLQUERY")

if [ "$WARNING" -ne 0 ] || [ "$CRITICAL" -ne 0 ]; then
    if [ "$DBSIZE" -ge $CRITICAL ]; then
        echo "CRITICAL|size=${DBSIZE}MB;$WARNING;$CRITICAL"
        exit 2
    elif [ "$DBSIZE" -ge $WARNING ]; then
        echo "WARNING|size=${DBSIZE}MB;$WARNING;$CRITICAL"
        exit 1
    fi
fi

echo "OK|size=${DBSIZE}MB;$WARNING;$CRITICAL"
exit 0
