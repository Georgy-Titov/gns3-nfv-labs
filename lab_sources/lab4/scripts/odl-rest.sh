#!/usr/bin/env bash
# Вызвать из корня lab4: source scripts/odl-rest.sh
export STUDENT=titov N=87
export ODL=http://10.104.87.100:8181
odl_get() {
  curl -sS -u admin:admin -H 'Accept: application/json' "$ODL/rests/data/$1" | jq .
}
put_flow() { # put_flow <1|2> <id> <файл.json>
  curl -sS -u admin:admin -X PUT -H 'Content-Type: application/json' -H 'Accept: application/json' -d @"$3" \
    -o /dev/null -w "PUT $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
del_flow() { # del_flow <1|2> <id>
  curl -sS -u admin:admin -X DELETE \
    -o /dev/null -w "DELETE $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
