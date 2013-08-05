#! /usr/bin/env bash

LOG_PREFIX="[prod-backup]"

usage()
{
    cat << EOF
usage: $0 options

This script run the test1 or test2 over a machine.

OPTIONS:
   -h           Show this message
   -l <login>   RHC login (required)
   -a <name>    App name to use (default=web01)
   -d <path>    Mongo database dump dir (produced by mongodump)
   -c <path>    victims.cfg file to be used
EOF
    exit 0
}

RHC_LOGIN=
APP_NAME=web01
MONGODB_DUMP=mongo.dump
VICTIMS_CFG=victimsweb.cfg

while getopts "hl:a:d:c:" OPTION; do
     case $OPTION in
         h) usage;;
         l) RHC_LOGIN=$OPTARG;;
         a) APP_NAME=$OPTARG;;
         d) MONGODB_DUMP=$OPTARG;;
         c) VICTIMS_CFG=$OPTARG;;
         ?) usage;;
     esac
done

if [ -z $RHC_LOGIN ]; then
     usage
fi

echo "$LOG_PREFIX Using login: ${RHC_LOGIN}"
SSH_HOST=$(rhc app show -l ${RHC_LOGIN} -a ${APP_NAME} | grep "SSH:" | cut -d':' -f2 | sed s/'^[ ]*'/''/)
SSH_CMD="rhc ssh -l ${RHC_LOGIN} -a ${APP_NAME}"
DATA_DIR=$(${SSH_CMD} "echo \$OPENSHIFT_DATA_DIR" | sed s='/$'=''=)
REPO_DIR=$(${SSH_CMD} "echo \$OPENSHIFT_REPO_DIR" | sed s='/$'=''=)

echo "$LOG_PREFIX Preparing database backup"
$SSH_CMD "mongodump -d \$OPENSHIFT_APP_NAME -h \$OPENSHIFT_MONGODB_DB_HOST -u \$OPENSHIFT_MONGODB_DB_USERNAME -p \$OPENSHIFT_MONGODB_DB_PASSWORD --port \$OPENSHIFT_MONGODB_DB_PORT --out \$OPENSHIFT_DATA_DIR/mongodb.dump"
echo "$LOG_PREFIX Downloading database backup"
scp -r $SSH_HOST:$DATA_DIR/mongodb.dump "${MONGODB_DUMP}"
$SSH_CMD "rm -rf \$OPENSHIFT_DATA_DIR/mongodb.dump"
echo ""

echo "$LOG_PREFIX Downloading config backup"
scp $SSH_HOST:$REPO_DIR/config/victimsweb.cfg "${VICTIMS_CFG}"
echo ""

echo "$LOG_PREFIX Backup complete! Have a nice day!"
