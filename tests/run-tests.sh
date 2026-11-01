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
assert_line "direct PurpleAir URL" "PurpleAir URL: http://10.24.170.191/json" "$out"
assert_line "outdoor PM2.5 source" "PM2.5 source: atm (channel A/B average)" "$out"

mkdir -p "$TMP/config-discovery" "$TMP/config-launcher"
sed 's|^PURPLEAIR_URL=.*|PURPLEAIR_URL="http://10.0.0.7/json"|' \
    "$PROJECT/meteobridge-aqi.conf" > "$TMP/config-discovery/meteobridge-aqi.conf"
cp "$PROJECT/meteobridge-aqi.plugin" "$TMP/config-launcher/temporary.plugin"
chmod 0755 "$TMP/config-launcher/temporary.plugin"
out=$(METEOBRIDGE_SCRIPTS_DIR="$TMP/config-discovery" \
    "$TMP/config-launcher/temporary.plugin" --show-source)
assert_line "configuration discovery outside launch directory" "PurpleAir URL: http://10.0.0.7/json" "$out"

mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$AQI_MOCK_ARGS"
printf '%s\n' "${AQI_MOCK_JSON:-{\"pm2_5_atm_b\":3.36,\"pm2_5_atm\":2.97,\"current_humidity\":100,\"uptime\":297480,\"period\":120}}"
EOF
chmod 0755 "$TMP/fakebin/curl"
out=$(PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/curl-args" \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 \
    "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "PurpleAir channel A/B average" "data3 317" "$out"
assert_line "AQI from averaged PurpleAir sample" "data0 1700" "$out"
assert_line "successful update reports healthy status" "data5 0" "$out"
if grep -Fxq -- '-fsS --max-time 10 http://10.24.170.191/json' "$TMP/curl-args" && \
   ! grep -Fq 'template.cgi' "$TMP/curl-args"; then
    echo "PASS: direct PurpleAir request avoids Meteobridge template.cgi"
    pass=$((pass+1))
else
    echo "FAIL: request did not use PurpleAir directly" >&2
    fail=$((fail+1))
fi

conf=$(new_config channel-fallback)
out=$(PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/fallback-args" \
    AQI_MOCK_JSON='{"pm2_5_atm":5.00,"current_humidity":40,"uptime":100,"period":120}' \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000010 \
    "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "single valid particle channel fallback" "data3 500" "$out"
assert_line "single channel fallback remains healthy" "data5 0" "$out"

conf=$(new_config frozen-source)
PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/frozen-args" \
    AQI_MOCK_JSON='{"pm2_5_atm":5,"pm2_5_atm_b":5,"current_humidity":40,"uptime":100,"period":120}' \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000000 \
    "$PROJECT/meteobridge-aqi.plugin" --once >/dev/null
out=$(PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/frozen-args" \
    AQI_MOCK_JSON='{"pm2_5_atm":5,"pm2_5_atm_b":5,"current_humidity":40,"uptime":100,"period":120}' \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000301 \
    "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "frozen PurpleAir response is rejected" "data5 100" "$out"

out=$(PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/reboot-args" \
    AQI_MOCK_JSON='{"pm2_5_atm":5,"pm2_5_atm_b":5,"current_humidity":40,"uptime":5,"period":120}' \
    METEOBRIDGE_AQI_CONFIG="$conf" AQI_TEST_EPOCH=1800000400 \
    "$PROJECT/meteobridge-aqi.plugin" --once)
assert_line "lower uptime is accepted as sensor reboot" "data5 0" "$out"

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

# Meteobridge may start a plugin through a transient or renamed launcher path.
# The continuous process must keep updating internally after its launch path
# disappears. It must not depend on another copy beside the configuration.
mkdir -p "$TMP/lifecycle-scripts" "$TMP/lifecycle-runtime"
conf="$TMP/lifecycle-scripts/meteobridge-aqi.conf"
sed \
    -e "s|^STATE_DIR=.*|STATE_DIR=\"$TMP/lifecycle-state\"|" \
    -e 's/^MIN_HOURLY_COVERAGE=.*/MIN_HOURLY_COVERAGE=1/' \
    -e 's/^UPDATE_SECONDS=.*/UPDATE_SECONDS=1/' \
    "$PROJECT/meteobridge-aqi.conf" > "$conf"
cp "$PROJECT/meteobridge-aqi.plugin" "$TMP/lifecycle-runtime/temporary-launcher.plugin"
chmod 0755 "$TMP/lifecycle-runtime/temporary-launcher.plugin"
PATH="$TMP/fakebin:$PATH" AQI_MOCK_ARGS="$TMP/lifecycle-curl-args" \
    METEOBRIDGE_AQI_CONFIG="$conf" \
    "$TMP/lifecycle-runtime/temporary-launcher.plugin" \
    > "$TMP/lifecycle-output" 2> "$TMP/lifecycle-error" &
lifecycle_pid=$!
mv "$TMP/lifecycle-runtime/temporary-launcher.plugin" "$TMP/lifecycle-runtime/launcher-was-relocated.plugin"
sleep 3
kill "$lifecycle_pid" 2>/dev/null || :
wait "$lifecycle_pid" 2>/dev/null || :
lifecycle_healthy=$(grep -c '^data5 0$' "$TMP/lifecycle-output" || :)
if [ "$lifecycle_healthy" -ge 2 ]; then
    echo "PASS: continuous worker survives relocated launch path"
    pass=$((pass+1))
else
    echo "FAIL: continuous worker stopped after launch path was relocated" >&2
    cat "$TMP/lifecycle-output" >&2
    cat "$TMP/lifecycle-error" >&2
    fail=$((fail+1))
fi

echo "$pass passed; $fail failed"
[ "$fail" -eq 0 ]
