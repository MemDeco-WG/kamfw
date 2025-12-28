#!/usr/bin/env sh
# Minimal integration tests for provider-only (hardlink) scheme in kamfw
# Usage:
#   KEEP=1 ./run.sh   # Keep test root for inspection
#
# This test suite assumes the module runtime scripts are available under
# ../../lib/kamfw (relative to this test directory).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KAMFW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTROOT="${SCRIPT_DIR}/tmp-$(date +%s)-$$"
MODULES_DIR="${TESTROOT}/modules"
KAM_DIR="${TESTROOT}/kam"   # override the real /data/adb/kam for testing

mkdir -p "${MODULES_DIR}" "${KAM_DIR}"

# helpers
sha_file() {
    _f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_f" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$_f" | awk '{print $NF}'
    else
        # fallback: small ad-hoc hash (not cryptographically guaranteed);
        # use md5sum if available, otherwise use file size+mtime
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$_f" | awk '{print $1}'
        else
            ls -l --full-time "$_f" 2>/dev/null | awk '{print $5 "-" $6}'
        fi
    fi
}

count_dir() {
    _d="$1"
    if [ -d "$_d" ]; then
        find "$_d" -maxdepth 1 -type f 2>/dev/null | wc -l | awk '{print $1}'
    else
        echo 0
    fi
}

fail() {
    echo "FAIL: $*" >&2
    echo "Test artifacts left in: ${TESTROOT}"
    if [ -z "${KEEP:-}" ]; then
        rm -rf "${TESTROOT}"
    fi
    exit 1
}

assert_eq() {
    _got="$1"; _want="$2"; _msg="$3"
    if [ "$_got" != "$_want" ]; then
        fail "${_msg}: expected='${_want}', got='${_got}'"
    fi
}

assert_ne() {
    _a="$1"; _b="$2"; _msg="$3"
    if [ "$_a" = "$_b" ]; then
        fail "${_msg}: values are equal ('${_a}')"
    fi
}

expect_file() {
    [ -e "$1" ] || fail "expected file '$1' to exist"
}

expect_no_file() {
    [ ! -e "$1" ] || fail "expected file '$1' to NOT exist"
}

prepare_module() {
    mod="$1"
    content="$2"
    moddir="${MODULES_DIR}/${mod}"
    mkdir -p "${moddir}/.local/bin" "${moddir}/lib"
    printf '%s\n' "$content" > "${moddir}/.local/bin/abin"
    chmod +x "${moddir}/.local/bin/abin" 2>/dev/null || true
    # point module's lib/kamfw to repository's lib/kamfw (so scripts are available)
    ln -sfn "${KAMFW_DIR}" "${moddir}/lib/kamfw"
}

prepare_module_with_lib() {
    mod="$1"
    bin_content="$2"
    lib_content="${3:-$2}"
    moddir="${MODULES_DIR}/${mod}"
    mkdir -p "${moddir}/.local/bin" "${moddir}/.local/lib" "${moddir}/lib"
    printf '%s\n' "$bin_content" > "${moddir}/.local/bin/abin"
    printf '%s\n' "$lib_content" > "${moddir}/.local/lib/alin"
    chmod +x "${moddir}/.local/bin/abin" 2>/dev/null || true
    ln -sfn "${KAMFW_DIR}" "${moddir}/lib/kamfw"
}

run_customize() {
    mod="$1"
    MODDIR="${MODULES_DIR}/${mod}"
    export MODDIR KAM_MODULE_ID="$mod"
    export KAM_DIR="${KAM_DIR}"
    # stub framework helpers used by scripts (no-op in tests)
    import() { :; }
    print() { :; }
    set_perm_recursive() { :; }
    setup_termux_env() { :; }
    # source customize directly (it will use lock.sh from module's lib/kamfw)
    . "${MODDIR}/lib/kamfw/__customize__.sh"
}

run_uninstall() {
    mod="$1"
    MODDIR="${MODULES_DIR}/${mod}"
    export MODDIR KAM_MODULE_ID="$mod"
    export KAM_DIR="${KAM_DIR}"
    # stub framework helpers used by scripts (no-op in tests)
    import() { :; }
    print() { :; }
    set_perm_recursive() { :; }
    . "${MODDIR}/lib/kamfw/__uninstall__.sh"
}

dump_state() {
    echo "=== STATE DUMP ==="
    echo "TESTROOT=${TESTROOT}"
    echo "KAM_DIR=${KAM_DIR}"
    echo "modules:"
    ls -la "${MODULES_DIR}" 2>/dev/null || true
    echo "providers:"
    find "${KAM_DIR}/providers" -maxdepth 3 -type f -ls 2>/dev/null || true
    echo "global bin:"
    ls -la "${KAM_DIR}/bin" 2>/dev/null || true
    echo "global lib:"
    ls -la "${KAM_DIR}/lib" 2>/dev/null || true
    echo "objects (should be unused in provider-only mode):"
    ls -la "${KAM_DIR}/objects" 2>/dev/null || true
    echo "=================="
}

# Test cases
echo "Running tests in ${TESTROOT}"
trap 'echo \"Error occurred. Dumping state:\"; dump_state; fail \"Test aborted\"' INT TERM HUP

# Test 1: Install A
echo "TEST 1: install module A"
prepare_module "A" "Hello-from-A"
run_customize "A"

expect_file "${KAM_DIR}/providers/bin/abin/A"
expect_file "${KAM_DIR}/bin/abin"

shaA=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaA" ] || fail "cannot compute sha for global bin/abin"

# Ensure provider and global are hardlinked to the same inode (hardlink scheme)
prov_inode=$(ls -i "${KAM_DIR}/providers/bin/abin/A" | awk '{print $1}')
glob_inode=$(ls -i "${KAM_DIR}/bin/abin" | awk '{print $1}')
assert_eq "$prov_inode" "$glob_inode" "provider and global should be hardlinks to the same inode"

echo " - ok: provider created, global hardlinked, sha=${shaA}"

# Test 2: Install B with different content
echo "TEST 2: install module B (different content)"
prepare_module "B" "Hello-from-B"
run_customize "B"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and B"

shaB=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaB" ] || fail "cannot compute sha for global bin/abin after B install"
assert_ne "$shaA" "$shaB" "global should point to B's content (last-wins)"

echo " - ok: B installed, providers=${nprov}, global sha=${shaB}"

# Test 3: Uninstall B
echo "TEST 3: uninstall module B"
run_uninstall "B"

# After uninstall, A should be restored as global
expect_file "${KAM_DIR}/bin/abin"
sha_after=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_after" "$shaA" "global should have reverted to A's sha after B uninstall"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "1" "providers should have only A after B uninstall"

echo " - ok: B uninstalled, reverted to A"

# Test 4: Install B2 identical content to A (no dedupe in provider-only mode)
echo "TEST 4: install module B2 (same content as A)"
prepare_module "B2" "Hello-from-A"
run_customize "B2"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and B2"

shaB2=$(sha_file "${KAM_DIR}/bin/abin")
# If contents are identical, sha may be equal; verify last-wins by checking inode equality
prov_b2_inode=$(ls -i "${KAM_DIR}/providers/bin/abin/B2" | awk '{print $1}')
glob_inode=$(ls -i "${KAM_DIR}/bin/abin" | awk '{print $1}')
assert_eq "$prov_b2_inode" "$glob_inode" "global should be hardlinked to B2 (last-wins)"

echo " - ok: B2 installed (provider-only), providers=${nprov}, global inode=${glob_inode}"

# Test 5: Uninstall B2 -> global should revert to A
echo "TEST 5: uninstall B2"
run_uninstall "B2"

sha_after2=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_after2" "$shaA" "global should revert to A after B2 uninstall"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "1" "providers should have A only after B2 uninstall"

echo " - ok: B2 uninstalled, A remains"

# Test 6: install module C (provider-only, same as others)
echo "TEST 6: install module C"
prepare_module "C" "Hello-from-C"
run_customize "C"

expect_file "${KAM_DIR}/providers/bin/abin/C"
expect_file "${KAM_DIR}/bin/abin"

shaC=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaC" ] || fail "cannot compute sha for global bin/abin after C install"
assert_ne "$shaC" "$shaA" "global should point to C's content"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and C"

echo " - ok: C installed, providers=${nprov}, global sha=${shaC}"

# Test 7: multi-provider winner ordering (mtime)
echo "TEST 7: multi-provider winner ordering"
prepare_module "P1" "P1-content"
run_customize "P1"
shaP1=$(sha_file "${KAM_DIR}/bin/abin")

prepare_module "P2" "P2-content"
run_customize "P2"
shaP2=$(sha_file "${KAM_DIR}/bin/abin")
assert_ne "$shaP2" "$shaP1" "P2 should win over P1"

prepare_module "P3" "P3-content"
run_customize "P3"
shaP3=$(sha_file "${KAM_DIR}/bin/abin")
assert_ne "$shaP3" "$shaP2" "P3 should be the current winner"

# Make P1 most-recent by touching its provider entry (without changing global)
touch "${KAM_DIR}/providers/bin/abin/P1" 2>/dev/null || true

# Uninstall P3 -> P1 (most recently touched) should become global
run_uninstall "P3"
sha_now=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_now" "$shaP1" "After removing P3, P1 (most recently touched) should be winner"

echo " - ok: winner selection by mtime works (P1)"

# Test 8: install module L with shared lib support
echo "TEST 8: lib installation and providers"
prepare_module_with_lib "L" "Hello-from-L-bin" "Hello-from-L-lib"
run_customize "L"

expect_file "${KAM_DIR}/lib/alin"
expect_file "${KAM_DIR}/providers/lib/alin/L"
expect_file "${KAM_DIR}/providers/bin/abin/L"

sha_lib=$(sha_file "${KAM_DIR}/lib/alin")
[ -n "$sha_lib" ] || fail "cannot compute sha for global lib/alin after L install"

echo " - ok: lib installation produced global lib and provider entries"

# cleanup: uninstall L, P1, P2, C, A
run_uninstall "L"
run_uninstall "P1"
run_uninstall "P2"
run_uninstall "C"
run_uninstall "A" || true  # A might be already replaced/removed by previous tests

echo "ALL TESTS PASSED"

# cleanup unless KEEP is set
if [ -z "${KEEP:-}" ]; then
    rm -rf "${TESTROOT}"
else
    echo "Keeping test root: ${TESTROOT} (set KEEP=0 to remove)"
fi

exit 0
