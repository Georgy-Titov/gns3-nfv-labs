#!/usr/bin/env bash
# По умолчанию: установить ВСЕ 9 JSON, включая ACL.
# Для Этапа 3 и после теста ACL: ./scripts/push-flows.sh --without-acl
set -euo pipefail
cd "$(dirname "$0")/.."
export ODL="${ODL:-http://10.104.87.100:8181}"
if [[ "${1:-}" != "" && "${1:-}" != "--without-acl" ]]; then
  echo 'Использование: scripts/push-flows.sh [--without-acl]' >&2
  exit 2
fi
for path in flows/*.json; do
  name="$(basename "$path" .json)"
  if [[ "${1:-}" == "--without-acl" && "$name" == acl-* ]]; then continue; fi
  case "$name" in
    s1-*|acl-*) switch=1 ;;
    s2-*) switch=2 ;;
    *) echo "Неизвестный коммутатор у файла: $path" >&2; exit 1 ;;
  esac
  id="titov-$name"
  json_id="$(jq -er '."flow-node-inventory:flow"[0].id' "$path")"
  [[ "$id" == "$json_id" ]] || { echo "Ошибка: id $json_id != $id" >&2; exit 1; }
  response="$(curl -sS -u admin:admin -X PUT -H 'Content-Type: application/json' -H 'Accept: application/json' \
      -d @"$path" -o /dev/null -w '%{http_code}' \
      "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A${switch}/flow-node-inventory:table=0/flow=$id")"
  printf 's%s %-25s HTTP %s\n' "$switch" "$id" "$response"
  case "$response" in 200|201|204) ;; *) echo "Ошибка установки $id; проверьте тело ответа curl -i" >&2; exit 1;; esac
done
