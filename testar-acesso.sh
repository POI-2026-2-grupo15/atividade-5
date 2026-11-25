#!/usr/bin/env bash
# Testa as três aplicações pelo IP público do load balancer poi-atividades.
set -euo pipefail
LB=${LB:-150.165.85.77}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "== CPU-bound (porta 10002)"
curl -fsS "http://$LB:10002/health"; echo
curl -fsS -H 'Content-Type: application/json' -d '{"data_size_mb":1,"iterations":2}' "http://$LB:10002/benchmark"; echo

echo "== IO-bound (porta 10003)"
curl -fsS "http://$LB:10003/health"; echo
curl -fsS -H 'Content-Type: application/json' -d '{"size_kb":1024}' "http://$LB:10003/io"; echo

echo "== Memory-bound (porta 10004)"
printf 'id,name,email,description\n1,Ana,ana@ex.com,a\n2,Bia,bia@ex.com,b\n' > "$TMP/a.csv"
printf 'id,name,email,description\n2,Bia,bia@ex.com,b\n3,Caio,caio@ex.com,c\n' > "$TMP/b.csv"
curl -fsS -F "files=@$TMP/a.csv" -F "files=@$TMP/b.csv" "http://$LB:10004/memory-test"; echo
