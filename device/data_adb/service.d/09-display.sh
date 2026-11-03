#!/system/bin/sh
# Match the Pixel 9 (tokay) display so DisplayMetrics matches Build.MODEL
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 4
wm size 1080x2424
wm density 422
