#!/bin/sh
#
# This script only executes test mode
#
. ./ci-common.sh	# ci-runtest and ci-snaptest have much in common

WAIT_LAUNCH=60		# wait before worrying about slow launch
PANIC_AFTER=200		# kill test after 200 seconds of inactivity

echo "color yellow/blue yellow/magenta
timeout=3

title=phantom ALL TESTS
kernel=(nd)/phantom -d=20 $UNATTENDED -- -test all
module=(nd)/classes
module=(nd)/pmod_test
boot 
" > $GRUB_MENU

dd if=/dev/zero of=snapcopy.img bs=4096 skip=1 count=1024 2> /dev/null
dd if=/dev/zero of=vio.img bs=4096 skip=1 count=1024 2> /dev/null

# take working copy of the Phantom disk
cp ../../oldtree/run_test/$DISK_IMG .

$QEMU $QEMU_OPTS &
QEMU_PID=$!

# wait for Phantom to start
ELAPSED=2
sleep 2

while [ $ELAPSED -lt $WAIT_LAUNCH ]
do
	[ -s $LOGFILE ] && break

	sleep 2
	kill -0 $QEMU_PID || break
	ELAPSED=`expr $ELAPSED + 2`
done

[ -s $LOGFILE ] || {
	ELAPSED=$PANIC_AFTER
	LOG_MESSAGE="$LOGFILE is empty"
}

while [ $ELAPSED -lt $PANIC_AFTER ]
do

	sleep 2
	kill -0 $QEMU_PID || break
	ELAPSED=`expr $ELAPSED + 2`

	tail -1 $LOGFILE | grep -q '^Press any' && \
		call_gdb $GDB_PORT "Test run panic"

	grep -q '^\(\. \)\?Panic' $LOGFILE && {
		sleep 15	# allow panic to finish properly
		EXIT_CODE=2
		break
	}
done

# check if finished in time
[ $ELAPSED -lt $PANIC_AFTER ] || {
	echo "

FATAL! Phantom stalled: ${LOG_MESSAGE:-no activity after $PANIC_AFTER seconds}"
	kill $QEMU_PID
	EXIT_CODE=3
}

[ "$SNAP_CI" ] || {
	grep -q 'TEST FAILED' $LOGFILE && {
		cp $LOGFILE test.log
		#preserve_log test.log
	}
	mv ${GRUB_MENU}.orig $GRUB_MENU
}

# perform final checks
grep -B 10 'Panic\|[^e]fault\|^EIP\|^- \|Stack:\|^T[0-9 ]' $LOGFILE && die "Phantom test run failed!"
grep 'SVN' $LOGFILE || die "Phantom test run crashed!"
# show test summary in output
grep '[Ff][Aa][Ii][Ll]\|TEST\|SKIP' $LOGFILE
grep 'FINISHED\|done, reboot' $LOGFILE || die "Phantom test run error!"

# submit all details into the CI log, cutting off ESC-codes
[ "$SNAP_CI" ] && cat $LOGFILE | sed 's/[^m]*m//g;s///g'
exit $EXIT_CODE
