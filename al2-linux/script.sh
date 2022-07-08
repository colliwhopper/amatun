#!/bin/sh
#set -x
VERSION=0.1

#TODO
# profile option to use users default aws profile if not inputted
# add separate standalone -d option to disconnect all SSM/SSH sessions (option created, just no code yet)
# variablise the ports used for SSM/SSH
# refine sleep 20 into a proper loop in establishing SSM session  section

############
#   help   #
############
help() {
  # Display Help
  echo "Amatun (Amazon Tunnel) Usage"
  echo
  echo "Syntax: ./amatun [-upr|h|v]"
  echo
  echo "options:"
  echo "-h this help function"
  echo "-p set aws profile to be used"
  echo "-r set aws region to be used"
  echo "-u set ssh user allowed to connect to rds access instance"
  echo "-v displays amatun version"
  echo
  echo "example: ./amatun -u sshuser -p aws-main-stg -r us-east-1"
  echo
}

###############
#   options   #
###############
while getopts "dhvp:r:u:" option; do
  case $option in
  d) # disconnect all SSM/SSH sessions
    PROFILE=$OPTARG ;;
  h) # display help
    help
    exit
    ;;
  p) # enter aws profile
    PROFILE=$OPTARG ;;
  r) # enter aws region
    REGION=$OPTARG ;;
  u) # enter ssh username
    SSHUSER=$OPTARG ;;
  v) # display amatun version
    echo "$VERSION"
    exit
    ;;
  \?) # Invalid option warning
    echo "Error: Invalid option, see ./amatun -h for help"
    exit 1
    ;;
  esac
done

#################
#   variables   #
#################
echo && echo '### variables ###'
INSTANCEID=$(aws ec2 describe-instances \
  --filters Name=tag:amatun,Values=true \
  --query 'Reservations[*].Instances[*].[InstanceId]' \
  --output text --profile $PROFILE --region $REGION)

DBARN=$(aws resourcegroupstaggingapi get-resources --tag-filters Key=amatun,Values=true \
  --resource-type-filters rds:db \
  --profile $PROFILE --region $REGION \
  --output text | cut -f2 | grep "rds")

DBID=$(aws rds describe-db-instances --db-instance-identifier $DBARN \
  --profile $PROFILE \
  --query "*[].Endpoint.Address" \
  --output text --region $REGION)

echo "DBARN = $DBARN"
echo "DBID = $DBID"
echo "PROFILE = $PROFILE"
echo "INSTANCEID = $INSTANCEID"
echo "REGION  = $REGION"
echo "SSHUSER = $SSHUSER"
echo

###########################################
#   terminate any existing SSM sessions   #
###########################################
echo '### checking for existing SSM sessions on port 9990 and terminating ###' && echo
if
  nc -z -w5 127.0.0.1 9990 >>/dev/null 2>&1
  [ "$?" -eq 1 ]
then
  echo 'no existing SSM session detected on port 9990, continuing...'
  echo
elif
  nc -z -w5 127.0.0.1 9990 >>/dev/null 2>&1
  [ "$?" -eq 0 ]
then
  echo 'SSM session already established on port 9990'

  SSMPIDS=''
  for PID in $(lsof -i :9990 | awk '! /PID/ {print $2}'); do
    SSMPIDS+="${PID} "
  done

  echo 'terminating existing SSM session PIDS:' "$SSMPIDS"
  for PID in $SSMPIDS; do
    kill -9 $PID >>/dev/null 2>&1 &
  done
  if
    nc -z -w5 127.0.0.1 9990 >>/dev/null 2>&1
    [ "$?" -eq 1 ]
  then
    echo 'SUCCESS - existing SSM session PIDS terminated'
    echo
  elif
    nc -z -w5 127.0.0.1 9990 >>/dev/null 2>&1
    [ "$?" -eq 0 ]
  then
    echo 'ERROR - existing SSM session PIDS:' "$SSMPIDS" 'processes NOT terminated successfully'
    exit 1
  fi
fi

################################
#   establishing SSM session   #
################################
echo '### establishing SSM Session ###'

INSTANCEID=$(aws ec2 describe-instances \
  --filters Name=tag:amatun,Values=true \
  --query 'Reservations[*].Instances[*].[InstanceId]' \
  --output text --profile $PROFILE --region $REGION)

until aws ssm start-session \
  --target $INSTANCEID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["22"], "localPortNumber":["9990"]}' \
  --profile $PROFILE --region $REGION >>/dev/null 2>&1 & do
  TIMEOUT=30
  CHECKS=0
  ((CHECKS++))
  printf '.'
  sleep 1
  if [ "$CHECKS" -ge "$TIMEOUT" ]; then
    echo '\nERROR - failed to establish SSM session $TIMEOUT second timeout reached'
    exit 1
  fi
done
echo 'SUCCESS'
echo

###################################
#   checking SSM session status   #
###################################
echo '### checking SSM session status ###'
TIMEOUT=30
CHECKS=0

while true; do
  ((CHECKS++))
  printf '.'
  sleep 1

  if
    nc -z -w5 127.0.0.1 9990 >>/dev/null 2>&1
    [ "$?" -eq 0 ]
  then
    echo
    echo 'SUCCESS - SSM session established and verified'
    echo
    break
  fi

  if [ "$CHECKS" -ge "$TIMEOUT" ]; then
    echo 'ERROR - SSM session failed to established - $TIMEOUT second timeout reached'
    echo
    exit 1
  fi
done

#####################################
#   check for existing SSH tunnel   #
#####################################
echo '### check for existing SSH tunnel ###'

SSHPID=$(lsof -nP +c 15 | grep -w "127.0.0.1:3388" | awk '{ print $2 }')

if
  nc -z -w5 127.0.0.1 3388 >>/dev/null 2>&1
  [ "$?" -eq 0 ]
then
  'no existing SSH tunnel detected on port 3388, continuing...'
  break
elif
  nc -z -w5 127.0.0.1 3388 >>/dev/null 2>&1
  [ "$?" -eq 0 ]
then
  echo 'SSH tunnel already established on port 3388, terminating existing tunnel process'
  echo SSH Tunnel PID="$SSMPID"
  echo terminating SSH PID "$SSHPID"
  kill -9 $SSHPID /dev/null 2>&1
  sleep 5
  if
    nc -z -w5 127.0.0.1 3388 >>/dev/null 2>&1
    [ "$?" -eq 1 ]
  then
    echo
    echo PID: "$SSHPID" terminated successfully, continuing...
  fi
fi
echo 'SUCCESS'
echo

############################
#   establish SSH tunnel   #
############################
echo '### establishing SSH tunnel ###'

ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -o "LogLevel=ERROR" $SSHUSER@localhost -p 9990 -N -L 3388:$DBID:3306 &
echo 'SUCCESS'
echo

#########################
##   verify SSH tunnel   #
#########################
echo '### checking SSH tunnel status ###'

TIMEOUT=30
CHECKS=0

while true; do
  ((CHECKS++))
  printf '.'
  sleep 1

  if
    nc -z -w5 127.0.0.1 3388 >>/dev/null 2>&1
    [ "$?" -eq 0 ]
  then
    echo
    echo 'SUCCESS - SSH tunnel established and verified'
    break
  fi

  if [ "$CHECKS" -ge "$TIMEOUT" ]; then
    echo 'ERROR - SSH tunnel failed to establish: $TIMEOUT second timeout reached'
    exit 1
  fi
done

echo
echo 'you may now connect to localhost:3388 to access your RDS database'
