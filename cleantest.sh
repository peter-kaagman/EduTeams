#! /usr/bin/env bash

rm ./db/eduteams.sqlite
sqlite3 db/eduteams.sqlite ".read ./db/schema.sql"
sqlite3 db/eduteams.sqlite ".read ./db/testdata.sql"
./scribble/createJaarlaag.pl
./getAzureTeams.pl
./vergelijk.pl
