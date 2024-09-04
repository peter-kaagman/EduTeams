#! /usr/bin/env bash

rm ./cache/eduteams.sqlite
sqlite3 ./cache/eduteams.sqlite ".read ./db/schema.sql"
sqlite3 ./cache/eduteams.sqlite ".read ./db/testdata.sql"
./scribble/createJaarlaag.pl
./getAzureTeams.pl
./vergelijk.pl
