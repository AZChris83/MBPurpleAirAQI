#!/bin/sh
set -eu

PROJECT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/meteobridge-aqi-tests.$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP"

pass=0
fail=0

new_config() {
    name=$1
    state="$TMP/$name-state"
    conf="$TMP/$name.conf"
    sed \
        -e "s|^STATE_DIR=.*|STATE_DIR=\"$state\"|" \
        -e 's/^MIN_HOURLY_COVERAGE=.*/MIN_HOURLY_COVERAGE=1/' \
        "$PROJECT/meteobridge-aqi.conf" > "$conf"
    printf '%s\n' "$conf"
}

assert_line() {
    description=$1 expected=$2 output=$3
    if printf '%s\n' "$output" | grep -qx "$expected"; then
        echo "PASS: $description"
        pass=$((pass+1))
    else
        echo "FAIL: $description (missing '$expected')" >&2
        echo "$output" >&2
        fail=$((fail+1))
    fi
}

conf=$(new_config breakpoints)
out=$(METEOBRIDGE_AQI_CONFIG="$conf" "$PROJECT/meteobridge-aqi.plugin" --show-source)
assert_line "station-qualified PM2.5 sensor" "PM2.5 sensor: air1!1pm" "$out"
assert_line "station-qualified RH sensor" "RH sensor: th1!0hum" "$out"

mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$AQI_MOCK_ARGS"
printf '%s\n' '12.3|0|45|0'
EOF
chmod 0755 "$TMP/fakebin/curl"
out=$(PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/curl-args" \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 \
    "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "template.cgi input parsing" "data3 1230" "$out"
assert_line "successful update reports healthy status" "data5 0" "$out"
if grep -Fq 'template=[air1!1pm-act:NA]|[air1!1pm-age.0:999999]|[th1!0hum-act:NA]|[th1!0hum-age.0:999999]' "$TMP/curl-args"; then
    echo "PASS: template.cgi uses station-qualified source and age"
    pass=$((pass+1))
else
    echo "FAIL: template.cgi request is not correctly qualified" >&2
    fail=$((fail+1))
fi

rm -rf "$TMP/breakpoints-state"

out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 9.0)
assert_line "EPA 2024 Good upper breakpoint" "data0 5000" "$out"

rm -rf "$TMP/breakpoints-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 9.1)
assert_line "EPA 2024 Moderate lower breakpoint" "data0 5100" "$out"

rm -rf "$TMP/breakpoints-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 125.5)
assert_line "EPA 2024 Very Unhealthy lower breakpoint" "data0 20100" "$out"

rm -rf "$TMP/breakpoints-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 225.5)
assert_line "EPA 2024 Hazardous lower breakpoint" "data0 30100" "$out"

rm -rf "$TMP/breakpoints-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 9.09)
assert_line "PM2.5 is truncated to one decimal" "data0 5000" "$out"

rm -rf "$TMP/breakpoints-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 400)
assert_line "AQI defaults to a 500 cap" "data0 50000" "$out"

rm -rf "$TMP/breakpoints-state"
sed -i 's/^AQI_CAP=.*/AQI_CAP=999/' "$conf"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 400)
assert_line "AQI above 500 continues the Hazardous slope" "data0 64900" "$out"

conf=$(new_config correction)
sed -i 's/^PURPLEAIR_CORRECTION=.*/PURPLEAIR_CORRECTION="epa_us"/' "$conf"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 100 50)
assert_line "EPA U.S.-wide PurpleAir correction" "data3 5384" "$out"

rm -rf "$TMP/correction-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 400 50)
assert_line "EPA extended high-smoke correction" "data3 24985" "$out"

rm -rf "$TMP/correction-state"
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 100)
assert_line "correction rejects missing humidity with RH status" "data5 200" "$out"

out=$(METEOBRIDGE_AQI_CONFIG="$TMP/does-not-exist.conf" "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "missing configuration still emits plugin data" "data5 300" "$out"

conf=$(new_config nowcast)
hour=1800000000
METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=$((hour-3500)) "$PROJECT/meteobridge-aqi.plugin" --sample 35.4 >/dev/null
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=$((hour+10)) "$PROJECT/meteobridge-aqi.plugin" --sample 35.4)
assert_line "NowCast after two usable recent hours" "data1 10000" "$out"
assert_line "NowCast category is Moderate" "data2 100" "$out"
assert_line "NowCast concentration output" "data4 3540" "$out"

conf=$(new_config weighting)
METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=$((hour-3500)) "$PROJECT/meteobridge-aqi.plugin" --sample 100 >/dev/null
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=$((hour+10)) "$PROJECT/meteobridge-aqi.plugin" --sample 10)
assert_line "NowCast clamps changing-condition weight at 0.5" "data4 4000" "$out"

conf=$(new_config stale)
out=$(METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 "$PROJECT/meteobridge-aqi.plugin" --sample 0)
assert_line "zero concentration remains valid" "data0 0" "$out"

echo "$pass passed; $fail failed"
[ "$fail" -eq 0 ]
