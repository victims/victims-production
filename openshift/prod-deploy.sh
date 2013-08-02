#! /usr/bin/env bash

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
   -b <branch>  upstream branch to use (default=deployed)
EOF
    exit 0
}

RHC_LOGIN=
APP_NAME=web01
MONGODB_DUMP=
VICTIMS_CFG=
VICTIMS_BRANCH=deployed

while getopts "hl:a:d:c:" OPTION; do
     case $OPTION in
         h) usage;;
         l) RHC_LOGIN=$OPTARG;;
         a) APP_NAME=$OPTARG;;
         d) MONGODB_DUMP=$OPTARG;;
         c) VICTIMS_CFG=$OPTARG;;
         b) VICTIMS_BRANCH=$OPTARG;;
         ?) usage;;
     esac
done

if [ -z $RHC_LOGIN ]; then
     usage
fi

echo "[prod-deploy] Using login: ${RHC_LOGIN}"

if [ -d "${APP_NAME}" ]; then
	echo "[prod-deploy] Backing up current git-clone"
	mv "${APP_NAME}" "${APP_NAME}.bak"
fi	

echo "[prod-deploy] Creating ${APP_NAME}"
rhc app create -l ${RHC_LOGIN} ${APP_NAME} mongodb-2.2 python-2.7 --scaling --gear-size medium --from-code git://github.com/victims/victims-server-openshift.git

# Skipping rockmongo as it does not scale
# rhc cartridge add rockmongo-1.1 -a ${APP_NAME}

if [ ! -d "$APP_NAME" ]; then
    echo "[prod-deploy] Application was not cloned!! Trying to clone now ..."
    rhc git-clone -l ${RHC_LOGIN} ${APP_NAME} || (echo "[prod-deploy] I tried & failed!!" && exit 1)
fi

SSH_HOST=$(rhc app show -l ${RHC_LOGIN} -a ${APP_NAME} | grep "SSH:" | cut -d':' -f2 | sed s/'^[ ]*'/''/)
SSH_CMD="rhc ssh -l ${RHC_LOGIN} -a ${APP_NAME}"
DATA_DIR=$(${SSH_CMD} "echo \$OPENSHIFT_DATA_DIR" | sed s='/$'=''=)

# database
if [ ! -z "${MONGODB_DUMP}" ]; then
    echo "[prod-deploy] Restoring database from backup..."
    if [ -d "${MONGODB_DUMP}" ]; then
        scp -r ${MONGODB_DUMP} $SSH_HOST:$DATA_DIR/mongodb.dump
	if [ $? -ne 0 ]; then
		echo "[prod-deploy] Failed to upload mongodb.dump"
		DB_SKIP=1
	fi
    else
        echo "[prod-deploy] ERROR: ${MONGODB_DUMP} not found or is not a directory"
	DB_SKIP=1
    fi
fi

if [ -z $DB_SKIP ]; then
    $SSH_CMD "mongorestore -h \$OPENSHIFT_MONGODB_DB_HOST -u \$OPENSHIFT_MONGODB_DB_USERNAME -p \$OPENSHIFT_MONGODB_DB_PASSWORD --port \$OPENSHIFT_MONGODB_DB_PORT \$OPENSHIFT_DATA_DIR/mongodb.dump"
    $SSH_CMD "rm -rf $DATA_DIR/mongodb.dump"
fi

echo "[prod-deploy] Reloading app with correct branch"
cd ${APP_NAME}
git remote add upstream https://github.com/victims/victims-server-openshift.git
sed -i /'VICTIMS_GIT_BRANCH'/d config/victimsweb.build.env
echo "VICTIMS_GIT_BRANCH=${VICTIMS_BRANCH}" >> config/victimsweb.build.env

#config
if [ ! -z "${VICTIMS_CFG}" ]; then
	echo "[prod-deploy] Restoring ${VICTIMS_CFG}"
	cp ${VICTIMS_CFG} config/victimsweb.cfg
	git add config/victimsweb.cfg
	git commit -m "Restoring app configuration"
fi

git add config/victimsweb.build.env
git commit -m "Switching to <${VICTIMS_BRANCH}> branch"
git push origin master
cd ../

echo "[prod-deploy] Deploy completed! Have a nice day!"
