#!/usr/bin/env sh
# Minimal integration tests for kamfw object-pool + providers behavior
# Usage:
#   ./run.sh
# Set KEEP=1 to preserve the test directory for inspection on failure.

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
        printf "nohash\n"
        return 1
    fi
}

count_dir() {
    _d="$1"
    if [ -d "$_d" ]; then
        # Only count regular files (objects/providers entries)
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
    echo "KAM_DIR=${KAM_DIR}"
    echo "objects:"
    ls -la "${KAM_DIR}/objects" 2>/dev/null || true
    echo "providers:"
    find "${KAM_DIR}/providers" -maxdepth 3 -type f -ls 2>/dev/null || true
    echo "global bin:"
    ls -la "${KAM_DIR}/bin" 2>/dev/null || true
    echo "global lib:"
    ls -la "${KAM_DIR}/lib" 2>/dev/null || true
    echo "=================="
}

# Test cases
echo "Running tests in ${TESTROOT}"
trap 'echo \"Error occurred. Dumping state:\"; dump_state; fail \"Test aborted\"' INT TERM HUP

# Test 1: Install A
echo "TEST 1: install module A"
prepare_module "A" "Hello-from-A"
run_customize "A"

expect_file "${KAM_DIR}/objects"
nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "1" "after A install there should be 1 object"

expect_file "${KAM_DIR}/providers/bin/abin/A"
expect_file "${KAM_DIR}/bin/abin"

shaA=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaA" ] || fail "cannot compute sha for global bin/abin"

# Ensure provider and global are hardlinked to the same inode
prov_inode=$(ls -i "${KAM_DIR}/providers/bin/abin/A" | awk '{print $1}')
glob_inode=$(ls -i "${KAM_DIR}/bin/abin" | awk '{print $1}')
assert_eq "$prov_inode" "$glob_inode" "provider and global should be hardlinks to the same inode"

echo " - ok: single object created, sha=${shaA}"

# Test 2: Install B with different content
echo "TEST 2: install module B (different content)"
prepare_module "B" "Hello-from-B"
run_customize "B"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "2" "after B (different) install there should be 2 objects"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and B"

shaB=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaB" ] || fail "cannot compute sha for global bin/abin after B install"
assert_ne "$shaA" "$shaB" "global should point to B's object (last-wins)"

echo " - ok: B installed, objects=${nobj}, providers=${nprov}, global sha=${shaB}"

# Test 3: Uninstall B
echo "TEST 3: uninstall module B"
run_uninstall "B"

# After uninstall, A should be restored as global
expect_file "${KAM_DIR}/bin/abin"
sha_after=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_after" "$shaA" "global should have reverted to A's sha after B uninstall"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "1" "B's object should be GC'ed (if unreferenced)"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "1" "providers should have only A after B uninstall"

echo " - ok: B uninstalled, reverted to A"

# Test 4: Install B2 identical content to A (dedupe)
echo "TEST 4: install module B2 (same content as A)"
prepare_module "B2" "Hello-from-A"
run_customize "B2"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "1" "after installing B2 with identical content there should still be 1 object (dedupe)"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and B2"

shaB2=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$shaB2" "$shaA" "global sha should equal A's sha (identical content)"

echo " - ok: B2 installed (deduped), providers=${nprov}, objects=${nobj}"

# Test 5: Uninstall B2 -> global should revert to A
echo "TEST 5: uninstall B2"
run_uninstall "B2"

sha_after2=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_after2" "$shaA" "global should revert to A after B2 uninstall"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "1" "object should remain (A still present)"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "1" "providers should have A only after B2 uninstall"

echo " - ok: B2 uninstalled, A remains"

# Test 6: install module C with no hash tool (fallback)
echo "TEST 6: install module C (no hash)"
nobj_before=$(count_dir "${KAM_DIR}/objects")
prepare_module "C" "Hello-from-C"
# Force the customize script into no-hash mode to exercise fallback behavior
KAMFW_FORCE_NO_HASH=1 run_customize "C"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "$nobj_before" "no new object should be created when hash tool missing"

expect_file "${KAM_DIR}/providers/bin/abin/C"
expect_file "${KAM_DIR}/bin/abin"

shaC=$(sha_file "${KAM_DIR}/bin/abin")
[ -n "$shaC" ] || fail "cannot compute sha for global bin/abin after C install"
assert_ne "$shaC" "$shaA" "global should point to C's content"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "2" "providers should include A and C"

echo " - ok: C installed without hash, providers=${nprov}, objects=${nobj}"

# Test 7: Uninstall C
echo "TEST 7: uninstall module C"
run_uninstall "C"

sha_afterC=$(sha_file "${KAM_DIR}/bin/abin")
assert_eq "$sha_afterC" "$shaA" "global should revert to A after C uninstall"

nobj=$(count_dir "${KAM_DIR}/objects")
assert_eq "$nobj" "1" "no objects for C should exist"

nprov=$(count_dir "${KAM_DIR}/providers/bin/abin")
assert_eq "$nprov" "1" "providers should have A only after C uninstall"

echo " - ok: C uninstalled, A remains"

echo "ALL TESTS PASSED"

# cleanup unless KEEP is set
if [ -z "${KEEP:-}" ]; then
    rm -rf "${TESTROOT}"
else
    echo "Keeping test root: ${TESTROOT} (set KEEP=0 to remove)"
fi

exit 0
