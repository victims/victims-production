#! /usr/bin/env bash

LOG_PREFIX="[prod-deploy]"

usage()
{
    cat << EOF
    usage: $0 options

    This script run the test1 or test2 over a machine.

    OPTIONS:
    -h          Show this message
    -l <login>  RHC login (required)
    -a <name>   App name to use (default=web01)
    -d <path>   Mongo database dump dir (produced by mongodump) 
                containing <path>/APP_NAME (if not db restore is skipped)
    -c <path>   victims.cfg file to be used
    -e          Use existing app
    -b <branch> upstream branch to use (default=deployed)
EOF
    exit 0
}

RHC_LOGIN=
APP_NAME=web01
MONGODB_DUMP=
VICTIMS_CFG=
VICTIMS_BRANCH=deployed
EXISTING_APP=

while getopts "hl:a:d:c:e" OPTION; do
    case $OPTION in
        h) usage;;
        l) RHC_LOGIN=$OPTARG;;
        a) APP_NAME=$OPTARG;;
        d) MONGODB_DUMP=$(realpath $OPTARG);;
        c) VICTIMS_CFG=$(realpath $OPTARG);;
        b) VICTIMS_BRANCH=$OPTARG;;
        e) EXISTING_APP=1;;
        ?) usage;;
    esac
done

if [ -z $RHC_LOGIN ]; then
    usage
fi

echo "$LOG_PREFIX Using login: ${RHC_LOGIN}"

if [ -z ${EXISTING_APP} ]; then
    if [ -d "${APP_NAME}" ]; then
        echo "$LOG_PREFIX Backing up current git-clone"
        mv "${APP_NAME}" "${APP_NAME}.bak"
    fi
    echo "$LOG_PREFIX Creating ${APP_NAME}"
    rhc app create -l ${RHC_LOGIN} ${APP_NAME} mongodb-2.2 python-2.7 --scaling --gear-size medium --from-code git://github.com/victims/victims-server-openshift.git
else
    echo "$LOG_PREFIX Skipping app creation, using an existing instance."
fi

# Skipping rockmongo as it does not scale
# rhc cartridge add rockmongo-1.1 -a ${APP_NAME}

if [ ! -d "$APP_NAME" ]; then
    echo "$LOG_PREFIX Application was not cloned!! Trying to clone now ..."
    rhc git-clone -l ${RHC_LOGIN} ${APP_NAME} || (echo "$LOG_PREFIX I tried & failed!!" && exit 1)
fi

SSH_HOST=$(rhc app show -l ${RHC_LOGIN} -a ${APP_NAME} | grep "SSH:" | cut -d':' -f2 | sed s/'^[ ]*'/''/)
SSH_CMD="rhc ssh -l ${RHC_LOGIN} -a ${APP_NAME}"
DATA_DIR=$(${SSH_CMD} "echo \$OPENSHIFT_DATA_DIR" | sed s='/$'=''=)

# database
if [ ! -z "${MONGODB_DUMP}" ]; then
    echo "$LOG_PREFIX Restoring database from backup..."
    if [ -d "${MONGODB_DUMP}" ]; then
        if [ ! -d "${MONGODB_DUMP}/${APP_NAME}" ]; then
            echo "$LOG_PREFIX Cound not locate ${MONGODB_DUMP}/${APP_NAME}. Skipping!"
            DB_SKIP=1
        else
            scp -r "${MONGODB_DUMP}" $SSH_HOST:$DATA_DIR/mongodb.dump
            if [ $? -eq 0 ]; then
                $SSH_CMD "mongorestore --drop -d \$OPENSHIFT_APP_NAME -h \$OPENSHIFT_MONGODB_DB_HOST -u \$OPENSHIFT_MONGODB_DB_USERNAME -p \$OPENSHIFT_MONGODB_DB_PASSWORD --port \$OPENSHIFT_MONGODB_DB_PORT \$OPENSHIFT_DATA_DIR/mongodb.dump/\$OPENSHIFT_APP_NAME"
                $SSH_CMD "rm -rf $DATA_DIR/mongodb.dump"
            else
                echo "$LOG_PREFIX Failed to upload mongodb.dump"
            fi
        fi
    else
        echo "$LOG_PREFIX ERROR: ${MONGODB_DUMP} not found or is not a directory"
    fi
fi

echo "$LOG_PREFIX Reloading app with correct branch"
cd ${APP_NAME}
ENV_COFIG=config/victimsweb.env
git remote add upstream https://github.com/victims/victims-server-openshift.git
sed -i /'VICTIMS_GIT_BRANCH'/d ${ENV_COFIG}
echo "VICTIMS_GIT_BRANCH=${VICTIMS_BRANCH}" >> ${ENV_COFIG}

#config
if [ ! -z "${VICTIMS_CFG}" ]; then
    echo "$LOG_PREFIX Restoring ${VICTIMS_CFG}"
    cp "${VICTIMS_CFG}" config/victimsweb.cfg
    git add config/victimsweb.cfg
    git commit -m "Restoring app configuration"
fi

git add ${ENV_COFIG}
git commit -m "Switching to <${VICTIMS_BRANCH}> branch"
git push origin master
cd ../

echo "$LOG_PREFIX Deploy completed! Have a nice day!"
