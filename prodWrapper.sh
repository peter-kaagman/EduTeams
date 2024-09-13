#! /usr/bin/env bash
#
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"


rm ${SCRIPTPATH}/cache/eduteams.sqlite
sqlite3 ${SCRIPTPATH}/cache/eduteams.sqlite ".read ${SCRIPTPATH}/db/schema.sql"
sleep 2

${SCRIPTPATH}/getUsers.pl && \
${SCRIPTPATH}/getMagister.pl && \
${SCRIPTPATH}/getAzureTeams.pl && \
${SCRIPTPATH}/vergelijk.pl
