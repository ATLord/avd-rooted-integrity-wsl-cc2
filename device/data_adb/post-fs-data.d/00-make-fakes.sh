#!/system/bin/sh
# ============================================================================
# 00-make-fakes.sh  — SINGLE SOURCE OF TRUTH + VERSION-ADAPTIVE GENERATION
#
# Runs FIRST at post-fs-data. It does two things:
#
#   1. Parse the active PIF profile (custom.pif.prop) into a small env file
#      (/data/adb/avd-fake/profile.env) that every later script sources. This
#      makes the device identity come from ONE place — the same file PIF uses to
#      spoof Build.* — so the per-partition props, the bind-mounted build.prop,
#      and the GMS-visible Build object can never disagree (a disagreement is
#      exactly what causes CANNOT_ATTEST_IDS / empty verdicts).
#
#   2. Generate the version-specific fake files FROM THE AVD's OWN LIVE PARTITION
#      so the setup adapts to ANY Android version automatically:
#        - vendor_build.prop / odm_build.prop : take the live /vendor[/odm] prop
#          file (which already has the correct version/sdk/patch for THIS image)
#          and rewrite ONLY the device-identity lines to the profile. This is the
#          piece that makes it work on Android 14/15/16/… without hand-editing.
#        - dt_compatible      : "<brand>,<device> <brand>,<device>-revc"
#        - security_patch.txt : system/boot/vendor = profile SECURITY_PATCH
#
# If the live partition file can't be read, it falls back to the committed
# static avd-fake/*.prop (validated for the default tokay / Android-16 profile).
#
# DESIGN NOTES / WHY THIS SHAPE:
#   * keymint attests ATTESTATION_ID_{BRAND,DEVICE,MODEL,MANUFACTURER,PRODUCT}
#     by reading the per-partition ro.product.*.* props AND the on-disk
#     /vendor/build.prop. They must all equal the profile, or attestation fails.
#   * keymint attests patch LEVELS, not the build-id string, so keeping the
#     partition's native version/sdk fields is safe and avoids claiming (say)
#     Android 16 on an Android 14 partition.
#   * cpuinfo / version / modules fakes are NOT regenerated here — they're
#     identity-neutral (Tensor CPU layout + a Pixel kernel banner) and the
#     committed static copies are fine on every Android version.
# ============================================================================

LOG=/data/adb/make-fakes.log
FAKE=/data/adb/avd-fake
TS=/data/adb/tricky_store
PIF=/data/adb/modules/playintegrityfix/custom.pif.prop

mkdir -p "$FAKE"
rm -f "$FAKE/profile.boot" "$FAKE/profile.env"

# pull "KEY=value" out of custom.pif.prop (first match; value may contain spaces)
pif() { sed -n "s/^$1=//p" "$PIF" 2>/dev/null | head -n1; }

{
  echo "=== $(date) make-fakes start ==="

  if [ ! -f "$PIF" ]; then
    echo "WARN: no PIF at $PIF — leaving committed static fakes in place"
    echo "=== done (no-op) ==="
    exit 1
  fi

  BRAND=$(pif BRAND);            DEVICE=$(pif DEVICE)
  MANUF=$(pif MANUFACTURER);     MODEL=$(pif MODEL)
  PRODUCT=$(pif PRODUCT);        FP=$(pif FINGERPRINT)
  SECPATCH=$(pif SECURITY_PATCH); BUILD_ID=$(pif ID)
  INCREMENTAL=$(pif INCREMENTAL)

  # Refuse to proceed on a half-parsed profile (prevents writing garbage that a
  # later bind mount would expose). Fall back to committed static files.
  missing=
  for k in BRAND DEVICE MANUF MODEL PRODUCT FP SECPATCH; do
    eval "v=\$$k"; [ -n "$v" ] || missing="$missing $k"
  done
  if [ -n "$missing" ]; then
    echo "WARN: profile missing:$missing — keeping committed static fakes"
    echo "=== done (fallback) ==="
    exit 1
  fi
  echo "profile: $BRAND/$DEVICE  $MODEL  fp=$FP  patch=$SECPATCH"

  # --- 1. profile.env (single source for 01 + 04 + anything else) -----------
  {
    echo "BRAND=\"$BRAND\""
    echo "DEVICE=\"$DEVICE\""
    echo "MANUFACTURER=\"$MANUF\""
    echo "MODEL=\"$MODEL\""
    echo "PRODUCT=\"$PRODUCT\""
    echo "FINGERPRINT=\"$FP\""
    echo "SECURITY_PATCH=\"$SECPATCH\""
    echo "BUILD_ID=\"$BUILD_ID\""
    echo "INCREMENTAL=\"$INCREMENTAL\""
  } > "$FAKE/profile.env"
  echo "wrote profile.env"

  # --- 2. vendor_build.prop from the LIVE partition (version-adaptive) -------
  # Rewrite only identity + qemu lines; keep native version/sdk/date/patch-level.
  if [ -r /vendor/build.prop ]; then
    sed -E \
      -e "s|^(ro\.product\.vendor\.brand=).*|\1$BRAND|" \
      -e "s|^(ro\.product\.vendor\.device=).*|\1$DEVICE|" \
      -e "s|^(ro\.product\.vendor\.manufacturer=).*|\1$MANUF|" \
      -e "s|^(ro\.product\.vendor\.model=).*|\1$MODEL|" \
      -e "s|^(ro\.product\.vendor\.name=).*|\1$PRODUCT|" \
      -e "s|^(ro\.vendor\.build\.fingerprint=).*|\1$FP|" \
      -e "s|^(ro\.boot\.qemu=).*|\10|" \
      -e "s|^(ro\.kernel\.qemu=).*|\10|" \
      /vendor/build.prop > "$FAKE/vendor_build.prop.new" 2>/dev/null
    # sanity: must still contain the identity line we need; else keep fallback
    if grep -q "^ro.product.vendor.device=$DEVICE" "$FAKE/vendor_build.prop.new"; then
      mv "$FAKE/vendor_build.prop.new" "$FAKE/vendor_build.prop"
      echo "generated vendor_build.prop from live /vendor/build.prop"
    else
      rm -f "$FAKE/vendor_build.prop.new"
      echo "WARN: generated vendor_build.prop failed sanity — kept static fallback"
    fi
  else
    echo "WARN: /vendor/build.prop unreadable — kept static vendor_build.prop"
  fi

  # --- odm_build.prop from the live partition -------------------------------
  if [ -r /vendor/odm/etc/build.prop ]; then
    sed -E \
      -e "s|^(ro\.product\.odm\.brand=).*|\1$BRAND|" \
      -e "s|^(ro\.product\.odm\.device=).*|\1$DEVICE|" \
      -e "s|^(ro\.product\.odm\.manufacturer=).*|\1$MANUF|" \
      -e "s|^(ro\.product\.odm\.model=).*|\1$MODEL|" \
      -e "s|^(ro\.product\.odm\.name=).*|\1$PRODUCT|" \
      /vendor/odm/etc/build.prop > "$FAKE/odm_build.prop.new" 2>/dev/null
    if [ -s "$FAKE/odm_build.prop.new" ]; then
      mv "$FAKE/odm_build.prop.new" "$FAKE/odm_build.prop"
      echo "generated odm_build.prop from live /vendor/odm/etc/build.prop"
    else
      rm -f "$FAKE/odm_build.prop.new"
    fi
  fi

  # --- 3. dt_compatible -----------------------------------------------------
  printf '%s,%s %s,%s-revc \n' "$BRAND" "$DEVICE" "$BRAND" "$DEVICE" > "$FAKE/dt_compatible"
  echo "wrote dt_compatible: $(cat "$FAKE/dt_compatible")"

  # --- 3b. spoofed_cmdline: align device name to the profile ----------------
  # /proc/cmdline is redirected to this file by 02-avd-deeper-spoof.sh. Keep its
  # androidboot.hardware / bootloader consistent with the profile device (the
  # committed template hardcoded a different Pixel, which contradicts a non-
  # matching profile). Edit in place; if anything looks off, leave the template.
  SC=/data/adb/susfs4ksu/spoofed_cmdline
  if [ -f "$SC" ]; then
    sed -E \
      -e "s/androidboot\.hardware=[A-Za-z0-9_]+/androidboot.hardware=$DEVICE/g" \
      -e "s/androidboot\.bootloader=[A-Za-z0-9._-]+/androidboot.bootloader=${DEVICE}-1.0-13344233/g" \
      "$SC" > "$SC.new" 2>/dev/null
    if grep -q "androidboot.hardware=$DEVICE" "$SC.new"; then
      mv "$SC.new" "$SC"; echo "aligned spoofed_cmdline to $DEVICE"
    else
      rm -f "$SC.new"
    fi
  fi

  # --- 4. tricky_store/security_patch.txt (must match the profile) ----------
  # Keyed per-component (system=/boot=/vendor=). NOT all= (that key is ignored).
  # Pin it immutable immediately: PIF's action.sh later truncates the system=
  # line (observed as "system=202605"), which is a hard integrity failure. The
  # chattr +i stops that; service.d/08-tee-broken.sh re-asserts it too.
  if [ -d "$TS" ]; then
    chattr -i "$TS/security_patch.txt" 2>/dev/null
    printf 'system=%s\nboot=%s\nvendor=%s\n' "$SECPATCH" "$SECPATCH" "$SECPATCH" > "$TS/security_patch.txt"
    chattr +i "$TS/security_patch.txt" 2>/dev/null
    echo "wrote + locked security_patch.txt = $SECPATCH"
  fi

  cat /proc/sys/kernel/random/boot_id > "$FAKE/profile.boot"
  echo "=== done $(date) ==="
} >> "$LOG" 2>&1
