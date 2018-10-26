#!/bin/bash

# Usage function
usage(){
  echo -e "Usage $0 -l LOGFILE -p PATTERN
Parameters:
 -l\tThe target logfile
 -p\tPattern is an extended regular expression
 -d\tDatetime format. Default value is '%b %-d %H'
 -m\tNumber of recent matches to be included in the output. Default value is 10
 -w\tNumber of pattern matches for warning status. Default value is 3
 -c\tNumber of pattern matches for critical status. Default value is 9
 -h\tHelp"
}

# default values
datetimef="%b %-d %H"
warning=3
critical=9
recent=10

# Parse arguments
while getopts "l:p:d:m:w:c:h" opt; do
  case $opt in
    l)  # logfile
      logfile=$OPTARG
      ;;
    p)  # patterns
      # patterns+=("$OPTARG")
      patterns=$OPTARG
      ;;
    d)  # datetime format
      datetimef=$OPTARG
      ;;
    m)  # number of matches to include in the output
      recent=$OPTARG
      ;;
    w)  # warning - number of pattern matches
      warning=$OPTARG
      ;;
    c)  # critical - number of pattern matches
      critical=$OPTARG
      ;;
    h)  # help
      usage
      exit 0
      ;;
    \?)
      echo "ERROR: Invalid option: -$OPTARG"
      usage
      exit 3
      ;;
    :)
      echo "ERROR: Option -$OPTARG requires an argument."
      exit 3
      ;;
  esac
done
shift $(( OPTIND -1 ))

# create the -e pattern1 ... -e pattnerN string
#params=""
#for pattern in "${patterns[@]}"; do
#  params+="-e \"$pattern\" "
#done
# remove trailing whitespace
#params="$(echo -e "${params}" | sed -e 's/[[:space:]]*$//')"

# check parameters
if [ ! "$logfile" ] || [ ! "$patterns" ]; then
    echo "UNKNOWN: Mandatory options are missing"
    exit 3
fi

# check if logfile exists
if [ ! -f "$logfile" ]; then
    echo "UNKNOWN: Logfile not found!"
    exit 3
fi

# current datetime
#datetime="$(date +'%-d %b %H')"
datetime="$(date +"$datetimef")"
output="$(grep "^$datetime" "$logfile" | egrep "$patterns")"
occurences=$(echo "$output" | wc -l)

# check if output is empty
if [ -z "$output" ]; then
    # when output is empty, occurences are still equal to 1
    occurences=0
fi

if [ "$occurences" -ge $critical ]; then
  state="CRITICAL"
  exit_code=2
elif [ "$occurences" -ge $warning ]; then
  state="WARNING"
  exit_code=1
elif [ "$occurences" -lt $warning ]; then
  state="OK"
  exit_code=0
fi

# output and perfdata
echo "$state: $occurences matches found|matches=$occurences;$warning;$critical"

# longoutput, most recent pattern matches
if [ $occurences -gt 0 ]; then
    echo "The $recent most recent pattern matches:"
    echo "$output" | tail -"$recent"
fi

exit $exit_code

