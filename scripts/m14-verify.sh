#!/usr/bin/env bash
# Module 14 live verification. Everything below is the real API's own output.
set -u
API=http://127.0.0.1:8000/api/v1
NAT=${1:-9999901409}

say () { printf '\n=== %s ===\n' "$1"; }

# The OTP send limiter counts a scripted run the same way it counts an attack,
# which is correct of it and inconvenient here. Cleared before each sign-in so
# a verification run does not measure its own rate limiting.
( cd /home/user/foodonthego/backend && php artisan cache:clear > /dev/null )

cd /home/user/foodonthego/mobile
export PATH="$PATH:/opt/flutter/bin"
TOKEN=$(dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart --raw "$NAT" 2>/dev/null | grep -E '^[0-9]+\|[A-Za-z0-9]+$' | tail -1)
AUTH="Authorization: Bearer $TOKEN"
JSON="Content-Type: application/json"
ACC="Accept: application/json"

say "who is signed in"
curl -s -H "$AUTH" -H "$ACC" "$API/customer/me" | python3 -m json.tool | head -12

FROM=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/places/search?q=green+park" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["place_id"])')
TO=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/places/search?q=jaipur+airport" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["place_id"])')
O=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/places/$FROM")
D=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/places/$TO")

BODY=$(python3 - "$O" "$D" <<'PY'
import json,sys
def loc(raw):
    p=json.loads(raw)["data"]
    return {"source_type":"PLACE_SEARCH","place_id":p["place_id"],
            "display_name":p["display_name"],"formatted_address":p["formatted_address"],
            "latitude":p["latitude"],"longitude":p["longitude"]}
print(json.dumps({"origin":loc(sys.argv[1]),"destination":loc(sys.argv[2])}))
PY
)

TRIP=$(curl -s -X POST -H "$AUTH" -H "$JSON" -H "$ACC" -d "$BODY" "$API/customer/trips" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["id"])')
curl -s -X POST -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/route/calculate" > /dev/null

REST=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/restaurants" | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]["restaurants"]
print([r for r in d if "Highway Spice" in r["name"]][0]["id"])')

ITEM=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/restaurants/$REST/menu" | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]["categories"]
print([i for c in d for i in c["items"] if i["name"]=="Paneer Tikka"][0]["id"])')

DETAIL=$(curl -s -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/restaurants/$REST/menu/items/$ITEM")
VAR=$(echo "$DETAIL" | python3 -c 'import sys,json;print([v for v in json.load(sys.stdin)["data"]["customization"]["variants"] if v["name"]=="Large"][0]["id"])')
OPT=$(echo "$DETAIL" | python3 -c 'import sys,json;print([o for g in json.load(sys.stdin)["data"]["customization"]["modifier_groups"] for o in g["options"] if o["name"]=="Mild"][0]["id"])')

curl -s -X POST -H "$AUTH" -H "$JSON" -H "$ACC" \
  -d "{\"item_id\":\"$ITEM\",\"variant_id\":\"$VAR\",\"modifier_option_ids\":[\"$OPT\"],\"quantity\":2}" \
  "$API/customer/trips/$TRIP/restaurants/$REST/cart/items" > /dev/null

PICK=$(curl -s -X POST -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/cart/pickup-options" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["pickup"]["recommended_option_id"])')
curl -s -X PUT -H "$AUTH" -H "$JSON" -H "$ACC" -d "{\"pickup_option_id\":\"$PICK\"}" \
  "$API/customer/trips/$TRIP/cart/pickup-selection" > /dev/null

say "checkout prepare — no commercial rule configured"
Q=$(curl -s -X POST -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/checkout/prepare")
echo "$Q" | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print(json.dumps({k:d[k] for k in ("checkout_id","status","currency","commercial","expires_at","ready_for_payment")}, indent=2))'

say "every instant in that body, and its offset"
echo "$Q" | python3 -c '
import sys,json,re
d=json.load(sys.stdin)["data"]
found={}
def walk(n,p=""):
    it = n.items() if isinstance(n,dict) else enumerate(n)
    for k,v in it:
        q = f"{p}.{k}" if p else str(k)
        if isinstance(v,(dict,list)): walk(v,q)
        elif isinstance(v,str) and re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$",v):
            found[q]=v
walk(d)
for k,v in found.items(): print(f"{k:44}{v}")
print()
print("distinct offsets:", sorted({v[-6:] for v in found.values()}))'

say "a body carrying its own amounts changes nothing"
T=$(curl -s -X POST -H "$AUTH" -H "$JSON" -H "$ACC" \
  -d '{"payable_total_minor":1,"items_subtotal_minor":1,"tax_minor":0,"discount_minor":9999}' \
  "$API/customer/trips/$TRIP/checkout/prepare")
echo "$T" | python3 -c '
import sys,json
print(json.dumps(json.load(sys.stdin)["data"]["commercial"], indent=2))'

say "with tax at 5% and a packaging fee of 15 rupees configured"
mysql -N -B foodonthego_local -e "UPDATE restaurants SET tax_rate_bps=500, packaging_fee_minor=1500 WHERE name LIKE '%Highway Spice%';"
curl -s -X POST -H "$AUTH" -H "$ACC" "$API/customer/trips/$TRIP/checkout/prepare" | python3 -c '
import sys,json
print(json.dumps(json.load(sys.stdin)["data"]["commercial"], indent=2))'
mysql -N -B foodonthego_local -e "UPDATE restaurants SET tax_rate_bps=NULL, packaging_fee_minor=NULL WHERE name LIKE '%Highway Spice%';"

say "another customer's checkout id"
( cd /home/user/foodonthego/backend && php artisan cache:clear > /dev/null )
OTHER=$(cd /home/user/foodonthego/mobile && dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart --raw 9999901499 2>/dev/null | grep -E '^[0-9]+\|[A-Za-z0-9]+$' | tail -1)
CID=$(echo "$Q" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["checkout_id"])')
curl -s -o /dev/null -w "status: %{http_code}\n" -X POST -H "Authorization: Bearer $OTHER" -H "$ACC" \
  "$API/customer/trips/$TRIP/checkout/$CID/validate"

say "nothing was bought"
for t in orders order_items payments pickup_codes checkout_quotes; do
  printf '%-18s %s\n' "$t" "$(mysql -N -B foodonthego_local -e "SHOW TABLES LIKE '$t';" | wc -l)"
done
echo "(1 = the table exists, 0 = it does not)"
mysql -N -B foodonthego_local -e "SELECT status, COUNT(*) FROM checkout_quotes GROUP BY status;"
