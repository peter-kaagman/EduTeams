#! /usr/bin/env bash
#
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo ${SCRIPTPATH}

if [ ! -f ${SCRIPTPATH}/cache/eduteams.sqlite ]; then
    sqlite3 ${SCRIPTPATH}/cache/eduteams.sqlite ".read ${SCRIPTPATH}/db/schema.sql"
fi

${SCRIPTPATH}/getUsers.pl && \
${SCRIPTPATH}/getMagister.pl && \
${SCRIPTPATH}/getAzureTeams.pl && \
${SCRIPTPATH}/vergelijk.pl
